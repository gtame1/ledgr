defmodule Ledgr.Domains.AumentaMiPension.ConversationBucketExport do
  @moduledoc """
  Exports every conversation with the operator tags ("buckets") we assigned
  to it, as CSV. One row per conversation — *including* untagged ones, which
  come back with `etiquetada = no` and an empty `buckets` cell, so the file
  doubles as a worklist of what still needs tagging.

  Filters mirror the Conversations page (status / funnel_stage / search) so
  whatever you're looking at on screen is what downloads — same contract as
  `HelloDoctor.ConversationFunnelExport`.

  The bucket columns are derived from `ConversationBucket.buckets/0`, which
  the schema documents as the single source of truth: adding a bucket there
  (plus field + migration) widens this CSV with no change here.

  ## Column layout

  Context first (`conversation_id` … `telefono`), then the tagging block:
  `etiquetada`, `buckets` (the labels of every ticked flag, joined), then
  one `X`/empty column per bucket for pivoting in Excel, then
  `notas_del_caso` and when the tagging happened.

  Timestamps render in Mexico City local time (the DB stores UTC), matching
  what the operator sees on the page.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Domains.AumentaMiPension.ConversationBuckets.ConversationBucket
  alias Ledgr.Domains.AumentaMiPension.Conversations
  alias Ledgr.Domains.AumentaMiPension.Customers.Customer
  alias Ledgr.Repo

  @tz "America/Mexico_City"
  @datetime_fmt "%Y-%m-%d %H:%M"

  # Excel-for-Windows reads a BOM-less UTF-8 CSV as CP-1252, which mangles
  # every accented bucket label ("Asesoría" → "AsesorÃ­a"). Same guard the
  # traspaso export uses.
  @bom "﻿"

  @doc """
  Returns the CSV body as a string.

  ## Options

    * `:status` — exact match on `conversations.status` ("active" / "closed")
    * `:funnel_stage` — exact match on `conversations.funnel_stage`
    * `:search` — substring match on customer name OR phone (case-insensitive)

  Blank/nil options are ignored, so passing the index page's params straight
  through exports everything when no filter is set.
  """
  def to_csv(opts \\ []) do
    opts |> fetch_rows() |> render()
  end

  @doc """
  The UTF-8 BOM plus the header row, as iodata — the first chunk of a streamed
  download.
  """
  def header_chunk, do: [@bom, header_line()]

  @doc "One CSV line as iodata, terminated with CRLF."
  def header_line, do: line(headers())

  @doc "Renders one fetched row as a CSV line (iodata), terminated with CRLF."
  def row_line(r), do: line(row(r))

  @doc """
  Lazily streams the matching rows. Must run inside a `Repo.transaction/2` —
  `Repo.stream/2` uses a database cursor, which is the point: the whole result
  set never exists in memory at once.
  """
  def stream_rows(opts \\ [], stream_opts \\ [max_rows: 500]) do
    opts |> base_query() |> Repo.stream(stream_opts)
  end

  @doc """
  How many rows the export would contain.

  Called before the response is put into chunked mode so that a bot-side schema
  drift still surfaces as a readable error page. Once the first chunk is out
  the status line is already sent and there is no way to report a failure.
  """
  def count_rows(opts \\ []) do
    opts |> base_query() |> exclude(:order_by) |> exclude(:select) |> subquery() |> Repo.aggregate(:count)
  end

  @doc """
  Renders already-fetched rows (the maps `fetch_rows/1` selects) as a CSV
  string, header included. Split out from `to_csv/1` so the column layout
  and quoting are testable without a database — the bot-owned tables this
  reads don't exist in the test repo.
  """
  def render(rows) when is_list(rows) do
    IO.iodata_to_binary([header_chunk() | Enum.map(rows, &row_line/1)])
  end

  @doc """
  CSV header row. One column per bucket sits between `num_buckets` and
  `notas_del_caso`, named after the bucket field.
  """
  def headers do
    ~w(conversation_id creada ultimo_mensaje status etapa_funnel cliente telefono
       etiquetada buckets num_buckets) ++
      Enum.map(ConversationBucket.bucket_fields(), &Atom.to_string/1) ++
      ~w(notas_del_caso etiquetada_el mensajes)
  end

  @doc """
  Renders one fetched row as a list of CSV fields. Pure — takes the map
  `fetch_rows/1` selects, so the column layout is testable without a DB.
  """
  def row(r) do
    bucket = r.bucket

    ticked =
      Enum.filter(ConversationBucket.buckets(), fn {field, _label} -> flag(bucket, field) end)

    [
      r.id,
      mx(r.created_at),
      mx(r.last_message_at),
      r.status,
      r.funnel_stage,
      r.cliente,
      r.telefono,
      if(tagged?(bucket), do: "sí", else: "no"),
      Enum.map_join(ticked, ", ", fn {_field, label} -> label end),
      length(ticked)
    ] ++
      Enum.map(ConversationBucket.bucket_fields(), fn field ->
        if flag(bucket, field), do: "X", else: ""
      end) ++
      [
        bucket && bucket.case_notes,
        bucket && mx(bucket.updated_at),
        r.mensajes
      ]
  end

  # ── internals ──────────────────────────────────────────────────────

  # Reuses the index page's filter builder so the CSV and the table can't
  # drift apart. `customers` is left-joined (not `assoc`-joined) because a
  # conversation can exist before the bot has a customer row for it, and
  # those must not silently vanish from the export.
  defp fetch_rows(opts) do
    opts |> base_query() |> Repo.all()
  end

  defp base_query(opts) do
    from(c in Conversations.filtered_query(opts),
      left_join: b in ConversationBucket,
      on: b.conversation_id == c.id,
      left_join: cu in Customer,
      on: cu.id == c.customer_id,
      order_by: [desc: c.last_message_at, desc: c.id],
      select: %{
        id: c.id,
        created_at: c.created_at,
        last_message_at: c.last_message_at,
        status: c.status,
        funnel_stage: c.funnel_stage,
        cliente:
          fragment("coalesce(nullif(?, ''), nullif(?, ''))", cu.full_name, cu.display_name),
        telefono: cu.phone,
        bucket: b,
        mensajes: fragment("(SELECT count(*) FROM messages m WHERE m.conversation_id = ?)", c.id)
      }
    )
  end

  defp line(fields), do: [Enum.map_intersperse(fields, ",", &csv_field/1), "\r\n"]

  # A left-join miss gives back either nil or a struct of nils, depending on
  # the Ecto version's struct-loading; treat both as "never tagged".
  defp tagged?(nil), do: false
  defp tagged?(%ConversationBucket{conversation_id: nil}), do: false
  defp tagged?(%ConversationBucket{}), do: true

  defp flag(nil, _field), do: false
  defp flag(%ConversationBucket{} = bucket, field), do: Map.get(bucket, field) == true

  # Stored UTC → Mexico City wall clock, so the CSV agrees with the page.
  defp mx(nil), do: nil

  defp mx(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> mx()
  end

  defp mx(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!(@tz) |> Calendar.strftime(@datetime_fmt)
  end

  defp csv_field(nil), do: ""
  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))
end
