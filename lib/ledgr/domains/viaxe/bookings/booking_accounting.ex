defmodule Ledgr.Domains.Viaxe.Bookings.BookingAccounting do
  @moduledoc """
  Accounting integration for the Viaxe booking lifecycle.

  Viaxe is a **pure travel agency**: customers pay service providers directly.
  Viaxe only earns a net commission from parent companies (Archer / Intermex)
  after a trip completes.

  Double-entry model:

    - Advance payment (before completion)
        DR Cash (1000)                / CR Advance Commission (2200)

    - Post-completion payment (settles receivable)
        DR Cash (1000)                / CR Commission Receivable (1100)

    - Booking completed
        DR Commission Receivable 1100  (net_comm - total_advances)
        DR Advance Commission    2200  (total_advances)
        CR Commission Revenue    4000  (commission_cents — Viaxe net)

    - Booking canceled (after completion only — reverses revenue)
        DR Commission Revenue    4000  / CR Commission Receivable (1100)

  Revenue (4000) is recognised only when the trip completes, limited to
  `commission_cents` (Viaxe's net after the parent-company deduction).

  All functions are idempotent: a second call with the same booking / payment
  returns the existing entry rather than creating a duplicate.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalEntry, Account}
  alias Ledgr.Domains.Viaxe.Bookings.BookingPayment

  @cash_code "1000"
  @commission_receivable "1100"
  @advance_commission_code "2200"
  @commission_revenue_code "4000"

  # ── Status-change dispatcher ─────────────────────────────────────────────

  def handle_status_change(booking, "completed"), do: record_booking_completed(booking)
  def handle_status_change(booking, "canceled"), do: record_booking_canceled(booking)
  def handle_status_change(_booking, _status), do: {:ok, nil}

  # ── Payment ──────────────────────────────────────────────────────────────
  # Routes to the correct credit account based on is_advance:
  #   advance=true  → DR Cash / CR Advance Commission (2200)
  #   advance=false → DR Cash / CR Commission Receivable (1100)

  def record_booking_payment(%{
        id: pay_id,
        booking_id: b_id,
        amount_cents: amt,
        is_advance: is_advance,
        cash_account_id: cash_acct_id
      }) do
    reference = "viaxe_payment_#{pay_id}"
    entry_type = "booking_payment"
    cr_code = if is_advance, do: @advance_commission_code, else: @commission_receivable

    idempotent(reference, entry_type, fn ->
      cash =
        if cash_acct_id,
          do: Repo.get!(Account, cash_acct_id),
          else: Accounting.get_account_by_code!(@cash_code)

      cr_acct = Accounting.get_account_by_code!(cr_code)
      label = if is_advance, do: "advance", else: "settlement"
      cr_label = if is_advance, do: "Advance commission", else: "Commission receivable"

      Accounting.create_journal_entry_with_lines(
        %{
          date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
          description: "Payment on booking ##{b_id} (#{label})",
          reference: reference,
          entry_type: entry_type
        },
        [
          %{
            account_id: cash.id,
            debit_cents: amt,
            credit_cents: 0,
            description: "Cash received — booking #{b_id}"
          },
          %{
            account_id: cr_acct.id,
            debit_cents: 0,
            credit_cents: amt,
            description: "#{cr_label} — booking #{b_id}"
          }
        ]
      )
    end)
  end

  # ── Booking Completed ────────────────────────────────────────────────────
  # Recognises net commission; absorbs any advance payments already received.
  #
  # Entry always balances:
  #   DR Commission Receivable (net_comm - advances)
  #   DR Advance Commission    (advances)
  #   CR Commission Revenue    (net_comm = commission_cents)

  def record_booking_completed(%{id: id, commission_cents: net_comm}) do
    reference = "viaxe_booking_#{id}_completed"
    entry_type = "booking_completed"

    idempotent(reference, entry_type, fn ->
      total_advances =
        from(p in BookingPayment,
          where: p.booking_id == ^id and p.is_advance == true,
          select: sum(p.amount_cents)
        )
        |> Repo.one()
        |> Kernel.||(0)

      receivable_dr = max(net_comm - total_advances, 0)

      recv = Accounting.get_account_by_code!(@commission_receivable)
      advance = Accounting.get_account_by_code!(@advance_commission_code)
      revenue = Accounting.get_account_by_code!(@commission_revenue_code)

      lines =
        [
          %{
            account_id: revenue.id,
            debit_cents: 0,
            credit_cents: net_comm,
            description: "Commission revenue — booking #{id}"
          }
        ]
        |> prepend_if(
          total_advances > 0,
          %{
            account_id: advance.id,
            debit_cents: total_advances,
            credit_cents: 0,
            description: "Clear advance commission — booking #{id}"
          }
        )
        |> prepend_if(
          receivable_dr > 0,
          %{
            account_id: recv.id,
            debit_cents: receivable_dr,
            credit_cents: 0,
            description: "Commission receivable — booking #{id}"
          }
        )

      Accounting.create_journal_entry_with_lines(
        %{
          date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
          description: "Booking ##{id} completed",
          reference: reference,
          entry_type: entry_type
        },
        lines
      )
    end)
  end

  # ── Booking Canceled ─────────────────────────────────────────────────────
  # Only records an entry when the booking was already completed (revenue was
  # recognised). Cancellations before completion have no accounting impact.
  #
  # Reversal:
  #   DR Commission Revenue    (net_comm)
  #   CR Commission Receivable (net_comm)

  def record_booking_canceled(%{id: id, commission_cents: net_comm, status: "completed"}) do
    reference = "viaxe_booking_#{id}_canceled"
    entry_type = "booking_canceled"

    idempotent(reference, entry_type, fn ->
      revenue = Accounting.get_account_by_code!(@commission_revenue_code)
      recv = Accounting.get_account_by_code!(@commission_receivable)

      Accounting.create_journal_entry_with_lines(
        %{
          date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
          description: "Booking ##{id} canceled (reverse revenue)",
          reference: reference,
          entry_type: entry_type
        },
        [
          %{
            account_id: revenue.id,
            debit_cents: net_comm,
            credit_cents: 0,
            description: "Reverse commission revenue — booking #{id}"
          },
          %{
            account_id: recv.id,
            debit_cents: 0,
            credit_cents: net_comm,
            description: "Reverse commission receivable — booking #{id}"
          }
        ]
      )
    end)
  end

  # Canceled before completion → no revenue was recognised; no entry needed.
  def record_booking_canceled(_booking), do: {:ok, nil}

  # ── Private helpers ──────────────────────────────────────────────────────

  defp idempotent(reference, entry_type, fun) do
    existing =
      from(je in JournalEntry,
        where: je.reference == ^reference and je.entry_type == ^entry_type
      )
      |> Repo.one()

    if existing, do: {:ok, existing}, else: fun.()
  end

  defp prepend_if(list, true, item), do: [item | list]
  defp prepend_if(list, false, _item), do: list
end
