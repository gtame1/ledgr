defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.DashboardMetrics
  alias Ledgr.Domains.HelloDoctor.DoctorPayoutImport
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts
  alias Ledgr.Domains.HelloDoctor.ExternalCostAccounting
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost

  import Ecto.Query, warn: false

  # ── Per-consultation payout list ────────────────────────────────

  def index(conn, params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.beginning_of_month(today)
    end_date = parse_date(params["end_date"]) || today
    doctor_id = blank_to_nil(params["doctor_id"])
    status = params["status"] || "pending"
    sort = params["sort"] || "date"
    dir = params["dir"] || default_dir(sort)

    rows =
      DoctorPayouts.list_consultations_with_payouts(start_date, end_date,
        doctor_id: doctor_id,
        status: status,
        sort: sort,
        dir: dir
      )

    totals = DoctorPayouts.summarize(rows)

    doctors =
      Ledgr.Repo.all(
        from d in Ledgr.Domains.HelloDoctor.Doctors.Doctor, order_by: [asc: d.name]
      )

    render(conn, :index,
      rows: rows,
      totals: totals,
      start_date: start_date,
      end_date: end_date,
      doctor_id: doctor_id,
      status: status,
      sort: sort,
      dir: dir,
      doctors: doctors,
      payment_methods:
        Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayout.payment_methods(),
      today: today
    )
  end

  defp default_dir("doctor"), do: "asc"
  defp default_dir(_), do: "desc"

  # ── Record a doctor payout for one or more consultations ────────

  def record_payout(conn, params) do
    consultation_ids =
      case params["consultation_ids"] do
        list when is_list(list) -> list
        str when is_binary(str) and str != "" -> String.split(str, ",", trim: true)
        _ -> []
      end

    attrs = %{
      doctor_id: params["doctor_id"],
      consultation_ids: consultation_ids,
      payout_date: params["payout_date"],
      amount: params["amount"],
      payment_method: params["payment_method"] || "bank_transfer",
      reference: blank_to_nil(params["reference"]),
      notes: blank_to_nil(params["notes"])
    }

    case DoctorPayouts.create_payout(attrs) do
      {:ok, payout} ->
        amount_pesos = payout.amount_cents / 100.0

        conn
        |> put_flash(
          :info,
          "Payout of $#{:erlang.float_to_binary(amount_pesos, decimals: 2)} MXN recorded " <>
            "for #{length(consultation_ids)} consultation(s)."
        )
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, "Failed to record payout: #{reason}")
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(
          :error,
          "Failed to record payout: #{format_errors(changeset)}"
        )
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, other} ->
        conn
        |> put_flash(:error, "Failed to record payout: #{inspect(other)}")
        |> redirect(to: dp(conn, "/doctor-payouts"))
    end
  end

  # ── Edit / update an existing payout ───────────────────────────

  def edit(conn, %{"id" => id}) do
    payout = DoctorPayouts.get_payout!(id)
    doctor = Ledgr.Repo.get!(Ledgr.Domains.HelloDoctor.Doctors.Doctor, payout.doctor_id)
    candidates = DoctorPayouts.list_payout_edit_candidates(payout)
    amount_pesos = (payout.amount_cents || 0) / 100.0

    render(conn, :edit,
      payout: payout,
      doctor: doctor,
      candidates: candidates,
      amount_pesos: amount_pesos,
      payment_methods:
        Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayout.payment_methods()
    )
  end

  def update(conn, %{"id" => id} = params) do
    payout = DoctorPayouts.get_payout!(id)

    consultation_ids =
      case params["consultation_ids"] do
        list when is_list(list) -> list
        str when is_binary(str) and str != "" -> String.split(str, ",", trim: true)
        _ -> []
      end

    attrs = %{
      consultation_ids: consultation_ids,
      payout_date: params["payout_date"],
      amount: params["amount"],
      payment_method: params["payment_method"] || "bank_transfer",
      reference: blank_to_nil(params["reference"]),
      notes: blank_to_nil(params["notes"])
    }

    case DoctorPayouts.update_payout(payout, attrs) do
      {:ok, updated} ->
        amount_pesos = updated.amount_cents / 100.0

        conn
        |> put_flash(
          :info,
          "Payout updated — $#{:erlang.float_to_binary(amount_pesos, decimals: 2)} MXN across " <>
            "#{length(consultation_ids)} consultation(s)."
        )
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_flash(:error, "Failed to update payout: #{reason}")
        |> redirect(to: dp(conn, "/doctor-payouts/#{id}/edit"))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, "Failed to update payout: #{format_errors(changeset)}")
        |> redirect(to: dp(conn, "/doctor-payouts/#{id}/edit"))

      {:error, other} ->
        conn
        |> put_flash(:error, "Failed to update payout: #{inspect(other)}")
        |> redirect(to: dp(conn, "/doctor-payouts/#{id}/edit"))
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp format_errors(%Ecto.Changeset{} = cs) do
    cs.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
    |> Enum.join("; ")
  end

  # ── Post single external cost to GL ────────────────────────────

  def post_cost(conn, %{"id" => id}) do
    cost = Repo.get!(ExternalCost, id)

    case ExternalCostAccounting.post_to_gl(cost) do
      {:ok, :already_posted, _} ->
        conn
        |> put_flash(:info, "Already posted to GL.")
        |> redirect(to: dp(conn, "/"))

      {:ok, updated} ->
        mxn = Float.round(updated.amount_mxn_cents / 100.0, 2)

        conn
        |> put_flash(
          :info,
          "Posted to GL: $#{:erlang.float_to_binary(mxn, decimals: 2)} MXN (JE ##{updated.journal_entry_id})."
        )
        |> redirect(to: dp(conn, "/"))

      {:error, :zero_amount} ->
        conn
        |> put_flash(:error, "Cannot post — amount is zero.")
        |> redirect(to: dp(conn, "/"))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to post to GL. Check logs.")
        |> redirect(to: dp(conn, "/"))
    end
  end

  # ── Post ALL unposted costs to GL ──────────────────────────────

  def post_all_costs(conn, _params) do
    result = ExternalCostAccounting.post_all_unposted()

    msg = "Posted #{result.posted} costs to GL"
    msg = if result.skipped > 0, do: "#{msg}, #{result.skipped} skipped", else: msg
    msg = if result.errors > 0, do: "#{msg}, #{result.errors} errors", else: msg

    flash = if result.errors > 0, do: :error, else: :info

    conn
    |> put_flash(flash, msg <> ".")
    |> redirect(to: dp(conn, "/"))
  end

  # ── Bulk CSV upload ─────────────────────────────────────────────

  def bulk_upload_form(conn, _params) do
    render(conn, :bulk_upload, errors: nil, rows: nil, csv_preview: nil)
  end

  def bulk_upload_submit(conn, %{"upload" => %{"file" => %Plug.Upload{path: path}}}) do
    csv = File.read!(path)

    case DoctorPayoutImport.parse(csv) do
      {:ok, %{rows: rows}} ->
        case DoctorPayoutImport.commit(rows) do
          {:ok, count} ->
            conn
            |> put_flash(:info, "Recorded #{count} doctor payout(s) successfully.")
            |> redirect(to: dp(conn, "/doctor-payouts"))

          {:error, row, reason} ->
            ref = row && row.doctor_id
            msg = "Failed to record payout for doctor #{ref}: #{inspect(reason)}"

            conn
            |> put_flash(:error, msg)
            |> render(:bulk_upload, errors: [{0, msg}], rows: rows, csv_preview: csv)
        end

      {:error, %{rows: rows, errors: errors}} ->
        conn
        |> put_flash(:error, "CSV has #{length(errors)} issue(s). Nothing was saved.")
        |> render(:bulk_upload, errors: errors, rows: rows, csv_preview: csv)
    end
  end

  def bulk_upload_submit(conn, _params) do
    conn
    |> put_flash(:error, "Please choose a CSV file to upload.")
    |> redirect(to: dp(conn, "/doctor-payouts/bulk-upload"))
  end

  @doc """
  Returns a pre-filled CSV template based on the current per-doctor payout
  report so the user can edit amounts and re-upload.
  """
  def bulk_template(conn, params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.beginning_of_month(today)
    end_date = parse_date(params["end_date"]) || today

    report = DashboardMetrics.doctor_payout_report(start_date, end_date)

    header = ["doctor_id", "doctor_name", "amount", "date", "description"]

    rows =
      Enum.map(report.rows, fn r ->
        [
          r.id,
          r.name,
          :erlang.float_to_binary(r.doctor_share + 0.0, decimals: 2),
          to_string(today),
          "Payout to #{r.name} — #{start_date} to #{end_date}"
        ]
      end)

    csv =
      [header | rows]
      |> Enum.map_join("", fn row ->
        row
        |> Enum.map(&csv_field/1)
        |> Enum.join(",")
        |> Kernel.<>("\r\n")
      end)

    filename = "doctor-payouts-template-#{start_date}-to-#{end_date}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end

  defp csv_field(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp csv_field(v) when is_binary(v) do
    if String.contains?(v, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(v, "\"", "\"\"")}")
    else
      v
    end
  end

  defp csv_field(other), do: csv_field(to_string(other))

  # ── Helpers ─────────────────────────────────────────────────────

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutHTML do
  use LedgrWeb, :html
  embed_templates "doctor_payout_html/*"

  def humanize_method("bank_transfer"), do: "Bank transfer"
  def humanize_method("cash"), do: "Cash"
  def humanize_method("spei"), do: "SPEI"
  def humanize_method("other"), do: "Other"
  def humanize_method(other), do: other

  @doc """
  Builds a query string for the doctor payouts page with the given overrides
  applied on top of the current filter/sort state. `nil` values drop the key.
  """
  def payouts_query(assigns, overrides) do
    base = %{
      "start_date" => to_string(assigns.start_date),
      "end_date" => to_string(assigns.end_date),
      "doctor_id" => assigns.doctor_id,
      "status" => assigns.status,
      "sort" => assigns.sort,
      "dir" => assigns.dir
    }

    base
    |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
    # Only drop truly empty values. Keep explicit "all" / "pending" so that
    # navigating via sort links preserves the user's filter choice.
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
    |> URI.encode_query()
  end

  @doc """
  Renders a sort indicator arrow for the column header — empty if the column
  isn't the active sort.
  """
  def sort_arrow(current_sort, current_dir, column) do
    cond do
      to_string(current_sort) != to_string(column) -> ""
      to_string(current_dir) == "asc" -> " ↑"
      true -> " ↓"
    end
  end

  @doc """
  Returns the direction the column should toggle to when clicked.
  """
  def next_dir(current_sort, current_dir, column) do
    if to_string(current_sort) == to_string(column) do
      if to_string(current_dir) == "asc", do: "desc", else: "asc"
    else
      case to_string(column) do
        "doctor" -> "asc"
        _ -> "desc"
      end
    end
  end
end
