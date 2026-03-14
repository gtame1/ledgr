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

    record_owed_change_ap(subscription, overpayment_cents):
      DR  Deferred Sub Revenue (2200)           [overpayment_cents]
      CR  Owed Change Payable (2300)            [overpayment_cents]

    record_change_given(subscription, change_given_cents, from_account_id):
      DR  Deferred Sub Revenue (2200)           [change_given_cents]
      CR  {from_account}                        [change_given_cents]

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
  @owed_change_ap_code      "2300"
  @sub_revenue_code         "4000"
  @class_revenue_code       "4010"
  @consultation_revenue_code "4020"
  @rental_revenue_code      "4030"

  # ── Subscription Payment ─────────────────────────────────────────────

  @doc """
  Records a subscription payment for the given amount.

    DR  Cash (1000)                  [amount_cents]
    CR  Deferred Sub Revenue (2200)  [amount_cents]

  Options:
    - `:payment_date` — defaults to today
    - `:note`         — optional description for the debit line

  Each call creates a unique journal entry (unique reference per payment),
  so multiple payments can be recorded on the same subscription.
  """
  def record_subscription_payment(subscription, amount_cents, opts \\ []) do
    plan = subscription.subscription_plan ||
      Repo.preload(subscription, :subscription_plan).subscription_plan

    payment_date = Keyword.get(opts, :payment_date, Date.utc_today())
    note         = Keyword.get(opts, :note)
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_sub_payment_#{subscription.id}_#{seq}"
    entry_type   = "subscription_payment"

    cash     = Accounting.get_account_by_code!(@cash_code)
    deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Subscription payment — #{plan.name} (sub ##{subscription.id})",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: cash.id,     debit_cents: amount_cents, credit_cents: 0,
          description: note || "Cash received — subscription ##{subscription.id}"},
        %{account_id: deferred.id, debit_cents: 0,            credit_cents: amount_cents,
          description: "Deferred subscription revenue — sub ##{subscription.id}"}
      ]
    )
  end

  # ── Owed Change AP ────────────────────────────────────────────────────

  @doc """
  When a subscription payment exceeds the amount owed, reclassifies the
  overpayment from Deferred Sub Revenue back to an AP liability.

    DR  Deferred Sub Revenue (2200)  [overpayment_cents]
    CR  Owed Change Payable (2300)   [overpayment_cents]

  Options:
    - `:payment_date` — defaults to today
  """
  def record_owed_change_ap(subscription, overpayment_cents, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, Date.utc_today())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_sub_owed_change_#{subscription.id}_#{seq}"
    entry_type   = "owed_change_ap"

    plan        = subscription.subscription_plan ||
      Repo.preload(subscription, :subscription_plan).subscription_plan
    deferred    = Accounting.get_account_by_code!(@deferred_sub_rev_code)
    owed_change = Accounting.get_account_by_code!(@owed_change_ap_code)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Owed change — #{plan.name} (sub ##{subscription.id})",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: deferred.id,    debit_cents: overpayment_cents, credit_cents: 0,
          description: "Reverse excess deferred revenue — sub ##{subscription.id}"},
        %{account_id: owed_change.id, debit_cents: 0, credit_cents: overpayment_cents,
          description: "Owed change payable — sub ##{subscription.id}"}
      ]
    )
  end

  # ── Change Given Back ─────────────────────────────────────────────────

  @doc """
  When staff physically gives the member their change back, this reclassifies
  the overpayment from Deferred Sub Revenue to the source cash/bank account.

    DR  Deferred Sub Revenue (2200)  [change_given_cents]
    CR  {from_account}               [change_given_cents]

  Options:
    - `:payment_date` — defaults to today
  """
  def record_change_given(subscription, change_given_cents, from_account_id, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, Date.utc_today())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_sub_change_given_#{subscription.id}_#{seq}"
    entry_type   = "change_given"

    plan         = subscription.subscription_plan ||
      Repo.preload(subscription, :subscription_plan).subscription_plan
    deferred     = Accounting.get_account_by_code!(@deferred_sub_rev_code)
    from_account = Accounting.get_account!(from_account_id)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Change given back — #{plan.name} (sub ##{subscription.id})",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: deferred.id,      debit_cents: change_given_cents, credit_cents: 0,
          description: "Reverse excess deferred revenue — sub ##{subscription.id}"},
        %{account_id: from_account.id,  debit_cents: 0, credit_cents: change_given_cents,
          description: "Change given back to member — sub ##{subscription.id}"}
      ]
    )
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

  # ── Subscription Refund ──────────────────────────────────────────────

  @doc """
  Records a refund issued on cancellation of a subscription.

  Debits from Deferred Sub Revenue (2200) first; if the refund exceeds the deferred
  balance, the remainder is debited from Subscription Revenue (4000) (reversing
  already-recognized revenue). Credits the selected cash/bank account.

    DR  Deferred Sub Revenue (2200)   [min(refund_cents, sub.deferred_revenue_cents)]
    DR  Subscription Revenue (4000)   [remaining, if any]
    CR  Cash/Bank (from_account_id)   [refund_cents]
  """
  def record_subscription_refund(sub, refund_cents, from_account_id, date, note) do
    plan            = sub.subscription_plan
    description     = "Subscription refund — #{sub.customer.name} (#{plan.name})"
    seq             = :erlang.unique_integer([:positive, :monotonic])
    reference       = "vs_sub_refund_#{sub.id}_#{seq}"

    deferred_portion   = min(refund_cents, sub.deferred_revenue_cents)
    recognized_portion = refund_cents - deferred_portion

    deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)
    revenue  = Accounting.get_account_by_code!(@sub_revenue_code)

    dr_lines =
      (if deferred_portion > 0 do
        [%{account_id: deferred.id, debit_cents: deferred_portion, credit_cents: 0,
           description: "Reverse deferred revenue — sub ##{sub.id}"}]
      else [] end) ++
      (if recognized_portion > 0 do
        [%{account_id: revenue.id, debit_cents: recognized_portion, credit_cents: 0,
           description: "Reverse recognized revenue — sub ##{sub.id}"}]
      else [] end)

    lines =
      dr_lines ++
      [%{account_id: from_account_id, debit_cents: 0, credit_cents: refund_cents,
         description: note || "Refund issued — sub ##{sub.id}"}]

    Accounting.create_journal_entry_with_lines(
      %{
        date:        date,
        description: description,
        reference:   reference,
        entry_type:  "subscription_refund"
      },
      lines
    )
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
