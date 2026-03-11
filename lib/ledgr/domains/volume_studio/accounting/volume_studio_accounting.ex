defmodule Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting do
  @moduledoc """
  Double-entry accounting integration for the Volume Studio domain.

  All functions are **idempotent**: calling them a second time with the same
  record returns the existing journal entry instead of creating a duplicate.

  Account codes (from VolumeStudio.account_codes/0):
    1000  Cash
    1100  Accounts Receivable
    1400  IVA Receivable
    2100  IVA Payable
    2200  Deferred Subscription Revenue
    4000  Subscription Revenue
    4010  Class Revenue
    4020  Consultation Revenue
    4030  Space Rental Revenue

  Journal entries:

    record_subscription_payment(subscription):
      DR  Cash (1000)                           [plan.price_cents]
      CR  Deferred Sub Revenue (2200)           [plan.price_cents]

    recognize_subscription_revenue(subscription, amount_cents):
      DR  Deferred Sub Revenue (2200)           [amount_cents]
      CR  Subscription Revenue (4000)           [amount_cents]

    record_class_payment(booking):
      DR  Cash (1000)                           [booking.paid_cents]
      CR  Class Revenue (4010)                  [booking.paid_cents]

    record_consultation_payment(consultation):
      DR  Cash (1000)                           [amount_cents + iva_cents]
      CR  Consultation Revenue (4020)           [amount_cents]
      CR  IVA Payable (2100)                    [iva_cents]  (only if > 0)

    record_space_rental_payment(rental):
      DR  Cash (1000)                           [amount_cents + iva_cents]
      CR  Space Rental Revenue (4030)           [amount_cents]
      CR  IVA Payable (2100)                    [iva_cents]  (only if > 0)
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @cash_code                "1000"
  @iva_payable_code         "2100"
  @deferred_sub_rev_code    "2200"
  @sub_revenue_code         "4000"
  @class_revenue_code       "4010"
  @consultation_revenue_code "4020"
  @rental_revenue_code      "4030"

  # ── Subscription Payment ─────────────────────────────────────────────

  @doc """
  Records a subscription payment.

    DR  Cash (1000)                  [plan.price_cents]
    CR  Deferred Sub Revenue (2200)  [plan.price_cents]

  The subscription must have `:subscription_plan` preloaded.
  """
  def record_subscription_payment(subscription) do
    plan = subscription.subscription_plan || Repo.preload(subscription, :subscription_plan).subscription_plan
    amount = plan.price_cents

    reference = "vs_sub_payment_#{subscription.id}"
    entry_type = "subscription_payment"

    idempotent(reference, entry_type, fn ->
      cash     = Accounting.get_account_by_code!(@cash_code)
      deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Subscription payment — #{plan.name} (sub ##{subscription.id})",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: cash.id,     debit_cents: amount, credit_cents: 0,
            description: "Cash received — subscription ##{subscription.id}"},
          %{account_id: deferred.id, debit_cents: 0,      credit_cents: amount,
            description: "Deferred subscription revenue — sub ##{subscription.id}"}
        ]
      )
    end)
  end

  # ── Subscription Revenue Recognition ─────────────────────────────────

  @doc """
  Recognizes a portion of deferred subscription revenue.

    DR  Deferred Sub Revenue (2200)  [amount_cents]
    CR  Subscription Revenue (4000)  [amount_cents]

  The reference includes today's date so each monthly recognition gets its own entry.
  """
  def recognize_subscription_revenue(subscription, amount_cents) do
    reference  = "vs_sub_recognize_#{subscription.id}_#{Date.utc_today()}"
    entry_type = "subscription_revenue_recognition"

    idempotent(reference, entry_type, fn ->
      deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)
      revenue  = Accounting.get_account_by_code!(@sub_revenue_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Revenue recognition — subscription ##{subscription.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: deferred.id, debit_cents: amount_cents, credit_cents: 0,
            description: "Deferred revenue recognised — sub ##{subscription.id}"},
          %{account_id: revenue.id,  debit_cents: 0,            credit_cents: amount_cents,
            description: "Subscription revenue — sub ##{subscription.id}"}
        ]
      )
    end)
  end

  # ── Class Payment ─────────────────────────────────────────────────────

  @doc """
  Records a drop-in class payment at check-in.

    DR  Cash (1000)          [booking.paid_cents]
    CR  Class Revenue (4010) [booking.paid_cents]
  """
  def record_class_payment(booking) do
    amount     = booking.paid_cents
    reference  = "vs_class_payment_#{booking.id}"
    entry_type = "class_payment"

    idempotent(reference, entry_type, fn ->
      cash    = Accounting.get_account_by_code!(@cash_code)
      revenue = Accounting.get_account_by_code!(@class_revenue_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Drop-in class payment — booking ##{booking.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: cash.id,    debit_cents: amount, credit_cents: 0,
            description: "Cash received — class booking ##{booking.id}"},
          %{account_id: revenue.id, debit_cents: 0,      credit_cents: amount,
            description: "Class revenue — booking ##{booking.id}"}
        ]
      )
    end)
  end

  # ── Consultation Payment ──────────────────────────────────────────────

  @doc """
  Records a consultation payment.

    DR  Cash (1000)                   [amount_cents + iva_cents]
    CR  Consultation Revenue (4020)   [amount_cents]
    CR  IVA Payable (2100)            [iva_cents]  (only if iva_cents > 0)
  """
  def record_consultation_payment(consultation) do
    amount     = consultation.amount_cents
    iva        = consultation.iva_cents || 0
    total      = amount + iva
    reference  = "vs_consult_payment_#{consultation.id}"
    entry_type = "consultation_payment"

    idempotent(reference, entry_type, fn ->
      cash    = Accounting.get_account_by_code!(@cash_code)
      revenue = Accounting.get_account_by_code!(@consultation_revenue_code)

      base_lines = [
        %{account_id: cash.id,    debit_cents: total,  credit_cents: 0,
          description: "Cash received — consultation ##{consultation.id}"},
        %{account_id: revenue.id, debit_cents: 0,      credit_cents: amount,
          description: "Consultation revenue — consultation ##{consultation.id}"}
      ]

      lines =
        if iva > 0 do
          iva_payable = Accounting.get_account_by_code!(@iva_payable_code)
          base_lines ++ [
            %{account_id: iva_payable.id, debit_cents: 0, credit_cents: iva,
              description: "IVA payable — consultation ##{consultation.id}"}
          ]
        else
          base_lines
        end

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Consultation payment — consultation ##{consultation.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        lines
      )
    end)
  end

  # ── Space Rental Payment ──────────────────────────────────────────────

  @doc """
  Records a space rental payment.

    DR  Cash (1000)                     [amount_cents + iva_cents]
    CR  Space Rental Revenue (4030)     [amount_cents]
    CR  IVA Payable (2100)              [iva_cents]  (only if iva_cents > 0)
  """
  def record_space_rental_payment(rental) do
    amount     = rental.amount_cents
    iva        = rental.iva_cents || 0
    total      = amount + iva
    reference  = "vs_rental_payment_#{rental.id}"
    entry_type = "space_rental_payment"

    idempotent(reference, entry_type, fn ->
      cash    = Accounting.get_account_by_code!(@cash_code)
      revenue = Accounting.get_account_by_code!(@rental_revenue_code)

      base_lines = [
        %{account_id: cash.id,    debit_cents: total,  credit_cents: 0,
          description: "Cash received — rental ##{rental.id}"},
        %{account_id: revenue.id, debit_cents: 0,      credit_cents: amount,
          description: "Space rental revenue — rental ##{rental.id}"}
      ]

      lines =
        if iva > 0 do
          iva_payable = Accounting.get_account_by_code!(@iva_payable_code)
          base_lines ++ [
            %{account_id: iva_payable.id, debit_cents: 0, credit_cents: iva,
              description: "IVA payable — rental ##{rental.id}"}
          ]
        else
          base_lines
        end

      Accounting.create_journal_entry_with_lines(
        %{
          date:        Date.utc_today(),
          description: "Space rental payment — rental ##{rental.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        lines
      )
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp idempotent(reference, entry_type, fun) do
    existing =
      from(je in JournalEntry,
        where: je.reference == ^reference and je.entry_type == ^entry_type
      )
      |> Repo.one()

    if existing, do: {:ok, existing}, else: fun.()
  end
end
