defmodule LedgrWeb.Domains.HelloDoctor.CorporateController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.BotAdmin
  alias Ledgr.Domains.HelloDoctor.CorporateSettlements
  alias Ledgr.Domains.HelloDoctor.CorporateUsage
  alias Ledgr.Domains.HelloDoctor.PatientSegments

  # ── List + create company ────────────────────────────────────────

  def index(conn, _params) do
    case BotAdmin.list_corporate_accounts() do
      {:ok, %{"accounts" => accounts} = body} ->
        render(conn, :index,
          accounts: accounts,
          count: Map.get(body, "count", length(accounts))
        )

      {:ok, other} ->
        # Defensive: bot returned an unexpected shape
        conn
        |> put_flash(
          :error,
          "Unexpected response from bot: #{inspect(other) |> String.slice(0, 200)}"
        )
        |> render(:index, accounts: [], count: 0)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't load corporate accounts: #{reason}")
        |> render(:index, accounts: [], count: 0)
    end
  end

  def new(conn, _params) do
    render(conn, :new, form: empty_form())
  end

  def create(conn, %{"account" => params}) do
    attrs = %{
      slug: Map.get(params, "slug", "") |> String.trim() |> String.downcase(),
      name: Map.get(params, "name", "") |> String.trim(),
      consultation_rate_mxn: parse_rate(Map.get(params, "consultation_rate_mxn"))
    }

    case BotAdmin.create_corporate_account(attrs) do
      {:ok, %{"slug" => slug}} ->
        conn
        |> put_flash(:info, "Created corporate account #{slug}.")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed: #{reason}")
        |> render(:new, form: params)
    end
  end

  # ── Show: account detail + member roster ─────────────────────────

  def show(conn, %{"slug" => slug} = params) do
    include_removed? = params["include_removed"] in ["true", "1", "on", "yes"]

    with {:ok, account} <- BotAdmin.get_corporate_account(slug),
         {:ok, members_body} <-
           BotAdmin.list_corporate_members(slug, include_removed: include_removed?) do
      members = Map.get(members_body, "members", [])

      member_tiers =
        members
        |> Enum.map(& &1["phone"])
        |> Enum.reject(&is_nil/1)
        |> PatientSegments.tiers_by_phone()

      member_count = Map.get(members_body, "count", 0)

      # Active employees drive cost-per-employee; fall back to total count.
      active_count =
        case Enum.count(members, &(&1["status"] == "active")) do
          0 -> member_count
          n -> n
        end

      usage = CorporateUsage.summary(account["id"], active_count, account["consultation_rate_mxn"])

      render(conn, :show,
        account: account,
        members: members,
        member_tiers: member_tiers,
        member_count: member_count,
        usage: usage,
        include_removed?: include_removed?
      )
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't load account #{slug}: #{reason}")
        |> redirect(to: dp(conn, "/corporate"))
    end
  end

  # ── PATCH: name / rate / status ──────────────────────────────────

  def update(conn, %{"slug" => slug, "account" => params}) do
    attrs =
      [
        {:name, Map.get(params, "name")},
        {:consultation_rate_mxn, parse_rate(Map.get(params, "consultation_rate_mxn"))}
      ]
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Map.new()

    if attrs == %{} do
      conn
      |> put_flash(:error, "Nothing to update.")
      |> redirect(to: dp(conn, "/corporate/#{slug}"))
    else
      case BotAdmin.update_corporate_account(slug, attrs) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Account updated.")
          |> redirect(to: dp(conn, "/corporate/#{slug}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Update failed: #{reason}")
          |> redirect(to: dp(conn, "/corporate/#{slug}"))
      end
    end
  end

  def toggle_status(conn, %{"slug" => slug}) do
    with {:ok, %{"status" => current}} <- BotAdmin.get_corporate_account(slug),
         next when next != current <- toggle(current),
         {:ok, _} <- BotAdmin.update_corporate_account(slug, %{status: next}) do
      conn
      |> put_flash(:info, "Account is now #{next}.")
      |> redirect(to: dp(conn, "/corporate/#{slug}"))
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't toggle status: #{reason}")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))

      _ ->
        conn
        |> put_flash(:error, "Unknown status; can't toggle.")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))
    end
  end

  defp toggle("active"), do: "suspended"
  defp toggle("suspended"), do: "active"
  defp toggle(_), do: nil

  # ── Members: bulk add + remove ───────────────────────────────────

  def add_members(conn, %{"slug" => slug, "phones" => raw}) do
    phones =
      raw
      |> to_string()
      |> String.split(["\n", ",", ";"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      phones == [] ->
        conn
        |> put_flash(:error, "Paste one phone per line.")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))

      true ->
        case BotAdmin.add_corporate_members(slug, phones) do
          {:ok, %{"added_count" => added}} ->
            conn
            |> put_flash(
              :info,
              "Added #{added} of #{length(phones)} phone(s). Duplicates and blanks were skipped."
            )
            |> redirect(to: dp(conn, "/corporate/#{slug}"))

          {:error, reason} ->
            conn
            |> put_flash(:error, "Couldn't add members: #{reason}")
            |> redirect(to: dp(conn, "/corporate/#{slug}"))
        end
    end
  end

  def remove_member(conn, %{"slug" => slug, "phone" => phone}) do
    case BotAdmin.remove_corporate_member(slug, phone) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Removed #{phone}.")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't remove member: #{reason}")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))
    end
  end

  # ── Invoice: HTML + CSV ──────────────────────────────────────────

  def invoice(conn, %{"slug" => slug} = params) do
    month = params["month"] || default_month()

    case BotAdmin.get_corporate_invoice(slug, month) do
      {:ok, body} ->
        # The bot invoice's subtotal (count × rate) can include cancelled /
        # refunded rows; the GL settlement clears the AR we actually booked
        # (`booked_ar_cents`), so surface both. `account["id"]` (the bot UUID)
        # is what corporate consults carry, needed to compute booked AR.
        account_id =
          case BotAdmin.get_corporate_account(slug) do
            {:ok, account} -> Map.get(account, "id")
            _ -> nil
          end

        booked_ar_cents = account_id && CorporateSettlements.booked_ar_cents(account_id, month)
        settlement = CorporateSettlements.settlement_for(slug, month)

        render(conn, :invoice,
          account_name: Map.get(body, "name"),
          slug: slug,
          month: month,
          rate: Map.get(body, "consultation_rate_mxn"),
          items: Map.get(body, "items", []),
          count: Map.get(body, "count", 0),
          booked_ar_cents: booked_ar_cents || 0,
          settlement: settlement,
          settlement_amount_cents:
            settlement && CorporateSettlements.settlement_amount_cents(settlement),
          deposit_accounts: CorporateSettlements.deposit_accounts(),
          today: Ledgr.Domains.HelloDoctor.today()
        )

      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't load invoice: #{reason}")
        |> redirect(to: dp(conn, "/corporate/#{slug}"))
    end
  end

  @doc """
  Records an employer payment against the (slug, month) invoice, posting the
  collection JE (`Dr <deposit> / Cr 1100`). One settlement per month.
  """
  def settle_invoice(conn, %{"slug" => slug} = params) do
    month = params["month"] || default_month()
    back = dp(conn, "/corporate/#{slug}/invoice?month=#{month}")

    account_name =
      case BotAdmin.get_corporate_account(slug) do
        {:ok, account} -> Map.get(account, "name") || slug
        _ -> slug
      end

    attrs = %{
      amount_cents: parse_amount_cents(params["amount"]),
      date: parse_date(params["date"]),
      deposit_code: params["deposit_account"],
      account_name: account_name
    }

    case CorporateSettlements.record_settlement(slug, month, attrs) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Recorded payment from #{account_name} for #{month}.")
        |> redirect(to: back)

      {:error, :already_settled} ->
        conn
        |> put_flash(:error, "This invoice is already marked paid for #{month}.")
        |> redirect(to: back)

      {:error, :invalid_amount} ->
        conn
        |> put_flash(:error, "Enter a payment amount greater than zero.")
        |> redirect(to: back)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Couldn't record the payment — check the logs.")
        |> redirect(to: back)
    end
  end

  def invoice_csv(conn, %{"slug" => slug} = params) do
    month = params["month"] || default_month()

    case BotAdmin.get_corporate_invoice(slug, month) do
      {:ok, body} ->
        csv = build_invoice_csv(body, slug, month)
        filename = "corporate-invoice-#{slug}-#{month}.csv"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, csv)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't build CSV: #{reason}")
        |> redirect(to: dp(conn, "/corporate/#{slug}/invoice?month=#{month}"))
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp empty_form, do: %{"slug" => "", "name" => "", "consultation_rate_mxn" => ""}

  defp parse_rate(nil), do: nil
  defp parse_rate(""), do: nil

  defp parse_rate(v) do
    case v |> to_string() |> String.trim() |> Integer.parse() do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  defp default_month do
    today = Ledgr.Domains.HelloDoctor.today()
    Calendar.strftime(today, "%Y-%m")
  end

  # Parses a pesos string ("135", "1350.50") to centavos; nil/invalid → 0 so
  # the settlement rejects it with :invalid_amount.
  defp parse_amount_cents(v) when is_binary(v) do
    case v |> String.trim() |> Float.parse() do
      {pesos, _} when pesos >= 0 -> round(pesos * 100)
      _ -> 0
    end
  end

  defp parse_amount_cents(_), do: 0

  defp parse_date(v) when is_binary(v) do
    case Date.from_iso8601(String.trim(v)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp build_invoice_csv(body, slug, month) do
    header = [
      "Consultation ID",
      "Date",
      "Type",
      "Status",
      "Rate (MXN)"
    ]

    rows =
      Enum.map(Map.get(body, "items", []), fn item ->
        [
          Map.get(item, "consultation_id"),
          Map.get(item, "date"),
          Map.get(item, "consultation_type"),
          Map.get(item, "status"),
          Map.get(item, "rate_mxn")
        ]
      end)

    banner = [
      ["Corporate invoice — #{slug}"],
      ["Month", month],
      ["Rate per consultation (MXN)", Map.get(body, "consultation_rate_mxn") || "(not set)"],
      ["Total consultations", Map.get(body, "count", length(rows))],
      []
    ]

    (banner ++ [header | rows])
    |> Enum.map_join("", &encode_row/1)
  end

  defp encode_row(row) when is_list(row) do
    row
    |> Enum.map(&csv_field/1)
    |> Enum.join(",")
    |> Kernel.<>("\r\n")
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

defmodule LedgrWeb.Domains.HelloDoctor.CorporateHTML do
  use LedgrWeb, :html
  embed_templates "corporate_html/*"

  def render_rate(nil), do: {:safe, "<span style=\"color: var(--text-muted);\">—</span>"}
  def render_rate(n) when is_integer(n), do: "$" <> Integer.to_string(n) <> " MXN"
  def render_rate(n), do: to_string(n)

  @doc "Format a MXN amount with thousands separators, e.g. `$1,234.50`."
  def fmt_mxn(n) when is_number(n) do
    whole = trunc(n)
    cents = round((n - whole) * 100)

    int_str =
      whole
      |> abs()
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    sign = if n < 0, do: "-", else: ""
    cents_str = cents |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}$#{int_str}.#{cents_str}"
  end

  def fmt_mxn(_), do: "$0.00"

  @doc "Format a centavos integer as a MXN amount, e.g. `13500 → $135.00`."
  def fmt_cents(cents) when is_integer(cents), do: fmt_mxn(cents / 100)
  def fmt_cents(_), do: "$0.00"

  @doc "Format ISO datetime as 'YYYY-MM-DD HH:MM' or pass through."
  def fmt_iso(nil), do: ""

  def fmt_iso(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
      _ -> iso
    end
  end

  def fmt_iso(other), do: to_string(other)
end
