defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.DashboardMetrics
  alias Ledgr.Domains.HelloDoctor.ExternalCostAccounting
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost
  alias Ledgr.Core.Accounting

  import Ecto.Query, warn: false

  # ── Doctor payout report ────────────────────────────────────────

  def index(conn, params) do
    today      = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.beginning_of_month(today)
    end_date   = parse_date(params["end_date"])   || today

    report = DashboardMetrics.doctor_payout_report(start_date, end_date)

    render(conn, :index,
      report:     report,
      start_date: start_date,
      end_date:   end_date
    )
  end

  # ── Record a doctor payout (mark as paid) ───────────────────────

  @doc """
  Records that HelloDoctor has paid a doctor.
  Creates a journal entry:
    DEBIT  2000 Doctor Payable   [amount_pesos]
    CREDIT 1010 Bank - MXN       [amount_pesos]
  """
  def record_payout(conn, %{"doctor_id" => doctor_id, "amount" => amount_str, "description" => description}) do
    amount_pesos = String.to_float(amount_str)
    amount_cents = round(amount_pesos * 100)

    doctor_payable = Accounting.get_account_by_code!("2000")
    bank_mxn       = Accounting.get_account_by_code!("1010")

    entry_attrs = %{
      date:        Ledgr.Domains.HelloDoctor.today(),
      entry_type:  "doctor_payout",
      reference:   "DoctorPayout-#{doctor_id}",
      description: description || "Doctor payout",
      payee:       "Doctor ##{doctor_id}"
    }

    lines = [
      %{account_id: doctor_payable.id, debit_cents: amount_cents,  credit_cents: 0,            description: "Clearing doctor payable — #{description}"},
      %{account_id: bank_mxn.id,       debit_cents: 0,             credit_cents: amount_cents,  description: "Bank transfer to doctor — #{description}"}
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, _entry} ->
        conn
        |> put_flash(:info, "Payout of $#{:erlang.float_to_binary(amount_pesos, decimals: 2)} MXN recorded successfully.")
        |> redirect(to: dp(conn, "/doctor-payouts"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to record payout: #{inspect(changeset)}")
        |> redirect(to: dp(conn, "/doctor-payouts"))
    end
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
        |> put_flash(:info, "Posted to GL: $#{:erlang.float_to_binary(mxn, decimals: 2)} MXN (JE ##{updated.journal_entry_id}).")
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
    msg = if result.errors  > 0, do: "#{msg}, #{result.errors} errors", else: msg

    flash = if result.errors > 0, do: :error, else: :info

    conn
    |> put_flash(flash, msg <> ".")
    |> redirect(to: dp(conn, "/"))
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp parse_date(nil), do: nil
  defp parse_date(""),  do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _        -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorPayoutHTML do
  use LedgrWeb, :html
  embed_templates "doctor_payout_html/*"
end
