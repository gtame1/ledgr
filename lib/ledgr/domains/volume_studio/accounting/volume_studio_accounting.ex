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
    2300  Owed Change Payable
    4000  Subscription Revenue
    4020  Consultation Revenue
    4030  Space Rental Revenue
    4040  Partner Fee Revenue

  Journal entries:

    record_subscription_payment(subscription, amount_cents):
      DR  Cash (1000)                           [amount_cents]
      CR  Deferred Sub Revenue (2200)           [base_portion]   (proportional)
      CR  IVA Payable (2100)                    [iva_portion]    (proportional, only if > 0)

    reverse_subscription_payment(original_entry):
      DR  Deferred Sub Revenue (2200)           [base_portion]
      DR  IVA Payable (2100)                    [iva_portion]    (only if > 0)
      CR  Cash (1000)                           [amount_cents]

    record_owed_change_ap(subscription, overpayment_cents):
      DR  Deferred Sub Revenue (2200)           [overpayment_cents]
      CR  Owed Change Payable (2300)            [overpayment_cents]

    record_change_given(subscription, change_given_cents, from_account_id):
      DR  Deferred Sub Revenue (2200)           [change_given_cents]
      CR  {from_account}                        [change_given_cents]

    recognize_subscription_revenue(subscription, amount_cents):
      DR  Deferred Sub Revenue (2200)           [amount_cents]
      CR  Subscription Revenue (4000)           [amount_cents]

    recognize_subscription_revenue_for_booking(subscription, booking, amount_cents):
      DR  Deferred Sub Revenue (2200)           [amount_cents]
      CR  Subscription Revenue (4000)           [amount_cents]
      (idempotent on booking ID — used for package per-class recognition)

    record_consultation_payment(consultation):
      DR  Cash (1000)                           [amount_cents + iva_cents]
      CR  Consultation Revenue (4020)           [amount_cents]
      CR  IVA Payable (2100)                    [iva_cents]  (only if > 0)

    record_space_rental_payment(rental, attrs):
      DR  Cash (1000)                           [attrs.amount_cents]
      CR  Space Rental Revenue (4030)           [revenue_portion]   (proportional)
      CR  IVA Payable (2100)                    [iva_portion]       (proportional, only if > 0)

    record_partner_fee(partner_id, amount_cents):
      DR  Cash (1000)                           [amount_cents]
      CR  Partner Fee Revenue (4040)            [amount_cents]
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry

  @cash_code                 "1000"
  @iva_payable_code          "2100"
  @deferred_sub_rev_code     "2200"
  @owed_change_ap_code       "2300"
  @sub_revenue_code          "4000"
  @consultation_revenue_code "4020"
  @rental_revenue_code       "4030"
  @partner_fee_revenue_code  "4040"

  # ── Subscription Payment ─────────────────────────────────────────────

  @doc """
  Records a subscription payment for the given amount.

    DR  Cash (1000)                  [amount_cents]
    CR  Deferred Sub Revenue (2200)  [base_portion]  (proportional)
    CR  IVA Payable (2100)           [iva_portion]   (proportional, only if > 0)

  Options:
    - `:payment_date` — defaults to today
    - `:note`         — optional description for the debit line

  Each call creates a unique journal entry (unique reference per payment),
  so multiple payments can be recorded on the same subscription.
  """
  def record_subscription_payment(subscription, amount_cents, opts \\ []) do
    plan = subscription.subscription_plan ||
      Repo.preload(subscription, :subscription_plan).subscription_plan

    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note         = Keyword.get(opts, :note)
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_sub_payment_#{subscription.id}_#{seq}"
    entry_type   = "subscription_payment"

    base  = max(plan.price_cents - (subscription.discount_cents || 0), 0)
    iva   = subscription.iva_cents || 0
    total = base + iva

    {base_portion, iva_portion} =
      if total > 0 do
        b = round(amount_cents * base / total)
        {b, amount_cents - b}
      else
        {amount_cents, 0}
      end

    paid_to_code = Keyword.get(opts, :paid_to_account_code, @cash_code)
    paid_to  = Accounting.get_account_by_code!(paid_to_code)
    deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)

    base_lines = [
      %{account_id: paid_to.id,  debit_cents: amount_cents,  credit_cents: 0,
        description: note || "Payment received — subscription ##{subscription.id}"},
      %{account_id: deferred.id, debit_cents: 0, credit_cents: base_portion,
        description: "Deferred subscription revenue — sub ##{subscription.id}"}
    ]

    lines =
      if iva_portion > 0 do
        iva_payable = Accounting.get_account_by_code!(@iva_payable_code)
        base_lines ++ [
          %{account_id: iva_payable.id, debit_cents: 0, credit_cents: iva_portion,
            description: "IVA payable — subscription ##{subscription.id}"}
        ]
      else
        base_lines
      end

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Subscription payment — #{plan.name} (sub ##{subscription.id})",
        reference:   reference,
        entry_type:  entry_type
      },
      lines
    )
  end

  # ── Subscription Payment Reversal ────────────────────────────────────

  @doc """
  Creates a reversing journal entry for a subscription payment, preserving the
  full audit trail (original entry is kept; this entry nets it to zero).

  Flips every debit/credit line from the original entry:
    DR  Deferred Sub Revenue (2200)  [base_portion]
    DR  IVA Payable (2100)           [iva_portion]  (only if present in original)
    CR  Cash (1000)                  [amount_cents]

  Idempotent on original entry ID — calling twice returns the existing reversal.

  Options:
    - `:payment_date` — defaults to today
  """
  def reverse_subscription_payment(%JournalEntry{} = original_entry, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference    = "vs_sub_payment_reversal_#{original_entry.id}"
    entry_type   = "subscription_payment_reversal"

    idempotent(reference, entry_type, fn ->
      original_with_lines =
        if Ecto.assoc_loaded?(original_entry.journal_lines) do
          original_entry
        else
          Repo.preload(original_entry, journal_lines: :account)
        end

      reversed_lines =
        Enum.map(original_with_lines.journal_lines, fn line ->
          %{
            account_id:   line.account_id,
            debit_cents:  line.credit_cents,
            credit_cents: line.debit_cents,
            description:  "Reversal: #{line.description}"
          }
        end)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        payment_date,
          description: "Payment reversal — #{original_entry.description}",
          reference:   reference,
          entry_type:  entry_type
        },
        reversed_lines
      )
    end)
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
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
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
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
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
  Recognizes a portion of deferred subscription revenue (time-based / on-cancellation).

    DR  Deferred Sub Revenue (2200)  [amount_cents]
    CR  Subscription Revenue (4000)  [amount_cents]

  The reference includes today's date so each monthly/cancellation recognition
  gets its own entry per subscription per day.
  """
  def recognize_subscription_revenue(subscription, amount_cents) do
    reference  = "vs_sub_recognize_#{subscription.id}_#{LedgrWeb.Helpers.DomainHelpers.today_mx()}"
    entry_type = "subscription_revenue_recognition"

    idempotent(reference, entry_type, fn ->
      deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)
      revenue  = Accounting.get_account_by_code!(@sub_revenue_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        LedgrWeb.Helpers.DomainHelpers.today_mx(),
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

  @doc """
  Recognizes deferred subscription revenue triggered by a specific class check-in.
  Used for package-type plans where revenue is earned per class attended
  (deferred ÷ classes remaining at time of check-in).

    DR  Deferred Sub Revenue (2200)  [amount_cents]
    CR  Subscription Revenue (4000)  [amount_cents]

  Idempotent on booking ID — safe to call multiple times for the same check-in.
  Uses a booking-specific reference that does not collide with the date-based
  reference used by `recognize_subscription_revenue/2`.
  """
  def recognize_subscription_revenue_for_booking(subscription, booking, amount_cents) do
    reference  = "vs_sub_recognize_booking_#{booking.id}"
    entry_type = "subscription_revenue_recognition"

    idempotent(reference, entry_type, fn ->
      deferred = Accounting.get_account_by_code!(@deferred_sub_rev_code)
      revenue  = Accounting.get_account_by_code!(@sub_revenue_code)

      Accounting.create_journal_entry_with_lines(
        %{
          date:        LedgrWeb.Helpers.DomainHelpers.today_mx(),
          description: "Package class revenue — sub ##{subscription.id}, booking ##{booking.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        [
          %{account_id: deferred.id, debit_cents: amount_cents, credit_cents: 0,
            description: "Deferred revenue — class attended, sub ##{subscription.id}"},
          %{account_id: revenue.id,  debit_cents: 0,            credit_cents: amount_cents,
            description: "Package class revenue — booking ##{booking.id}"}
        ]
      )
    end)
  end

  # ── Consultation Payment ──────────────────────────────────────────────

  @doc """
  Records a consultation payment.

  Accepts either just the consultation struct (uses consultation.amount_cents) or
  an attrs map to override amount, date, and note (used when the caller records a
  specific cash amount that may differ from the stored amount_cents).

    DR  Cash (1000)                   [amount_cents + iva_cents]
    CR  Consultation Revenue (4020)   [amount_cents]
    CR  IVA Payable (2100)            [iva_cents]  (only if iva_cents > 0)
  """
  def record_consultation_payment(consultation, attrs \\ %{}) do
    amount       = Map.get(attrs, :amount_cents, consultation.amount_cents)
    iva          = consultation.iva_cents || 0
    total        = amount + iva
    payment_date = Map.get(attrs, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note         = Map.get(attrs, :note)
    reference    = "vs_consult_payment_#{consultation.id}"
    entry_type   = "consultation_payment"

    paid_to_code = Map.get(attrs, :paid_to_account_code, @cash_code)

    idempotent(reference, entry_type, fn ->
      paid_to = Accounting.get_account_by_code!(paid_to_code)
      revenue = Accounting.get_account_by_code!(@consultation_revenue_code)

      base_lines = [
        %{account_id: paid_to.id, debit_cents: total,  credit_cents: 0,
          description: note || "Payment received — consultation ##{consultation.id}"},
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
          date:        payment_date,
          description: "Consultation payment — consultation ##{consultation.id}",
          reference:   reference,
          entry_type:  entry_type
        },
        lines
      )
    end)
  end

  @doc """
  When a consultation payment exceeds the amount owed, reclassifies the overpayment
  from Consultation Revenue to an AP liability.

    DR  Consultation Revenue (4020)  [overpayment_cents]
    CR  Owed Change Payable (2300)   [overpayment_cents]

  Options:
    - `:payment_date` — defaults to today
  """
  def record_consultation_owed_change_ap(consultation, overpayment_cents, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_consult_owed_change_#{consultation.id}_#{seq}"
    entry_type   = "consultation_owed_change_ap"

    revenue     = Accounting.get_account_by_code!(@consultation_revenue_code)
    owed_change = Accounting.get_account_by_code!(@owed_change_ap_code)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Owed change — consultation ##{consultation.id}",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: revenue.id,     debit_cents: overpayment_cents, credit_cents: 0,
          description: "Reverse excess consultation revenue — consultation ##{consultation.id}"},
        %{account_id: owed_change.id, debit_cents: 0, credit_cents: overpayment_cents,
          description: "Owed change payable — consultation ##{consultation.id}"}
      ]
    )
  end

  @doc """
  When staff physically gives the customer their change, reclassifies the overpayment
  from Consultation Revenue to the source cash/bank account.

    DR  Consultation Revenue (4020)  [change_given_cents]
    CR  {from_account}               [change_given_cents]
  """
  def record_consultation_change_given(consultation, change_given_cents, from_account_id, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_consult_change_given_#{consultation.id}_#{seq}"
    entry_type   = "consultation_change_given"

    revenue      = Accounting.get_account_by_code!(@consultation_revenue_code)
    from_account = Accounting.get_account!(from_account_id)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Change given back — consultation ##{consultation.id}",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: revenue.id,      debit_cents: change_given_cents, credit_cents: 0,
          description: "Reverse excess consultation revenue — consultation ##{consultation.id}"},
        %{account_id: from_account.id, debit_cents: 0, credit_cents: change_given_cents,
          description: "Change given back to customer — consultation ##{consultation.id}"}
      ]
    )
  end

  # ── Space Rental Payment ──────────────────────────────────────────────

  @doc """
  Records a (partial or full) space rental payment.

  Each call creates a unique journal entry, allowing multiple partial payments.
  The paid amount is split proportionally between rental revenue and IVA payable.

    DR  Cash (1000)                 [attrs.amount_cents]
    CR  Space Rental Revenue (4030) [revenue_portion]   (proportional)
    CR  IVA Payable (2100)          [iva_portion]       (proportional, only if > 0)

  attrs:
    - `:amount_cents`  — amount paid in this transaction
    - `:payment_date`  — defaults to today
    - `:note`          — optional description override
  """
  def record_space_rental_payment(rental, attrs) do
    paid         = Map.fetch!(attrs, :amount_cents)
    base         = rental.amount_cents
    iva          = rental.iva_cents || 0
    total        = base + iva
    payment_date = Map.get(attrs, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note         = Map.get(attrs, :note)

    {revenue_portion, iva_portion} =
      if total > 0 do
        rev = round(paid * base / total)
        {rev, paid - rev}
      else
        {paid, 0}
      end

    paid_to_code = Map.get(attrs, :paid_to_account_code, @cash_code)
    seq        = :erlang.unique_integer([:positive, :monotonic])
    reference  = "vs_rental_payment_#{rental.id}_#{seq}"
    entry_type = "space_rental_payment"

    paid_to = Accounting.get_account_by_code!(paid_to_code)
    revenue = Accounting.get_account_by_code!(@rental_revenue_code)

    base_lines = [
      %{account_id: paid_to.id, debit_cents: paid,             credit_cents: 0,
        description: note || "Payment received — rental ##{rental.id}"},
      %{account_id: revenue.id, debit_cents: 0, credit_cents: revenue_portion,
        description: "Space rental revenue — rental ##{rental.id}"}
    ]

    lines =
      if iva_portion > 0 do
        iva_payable = Accounting.get_account_by_code!(@iva_payable_code)
        base_lines ++ [
          %{account_id: iva_payable.id, debit_cents: 0, credit_cents: iva_portion,
            description: "IVA payable — rental ##{rental.id}"}
        ]
      else
        base_lines
      end

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Space rental payment — rental ##{rental.id}",
        reference:   reference,
        entry_type:  entry_type
      },
      lines
    )
  end

  @doc """
  When a rental payment exceeds the amount owed, reclassifies the overpayment
  from Rental Revenue to an AP liability.

    DR  Space Rental Revenue (4030)  [overpayment_cents]
    CR  Owed Change Payable (2300)   [overpayment_cents]
  """
  def record_rental_owed_change_ap(rental, overpayment_cents, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_rental_owed_change_#{rental.id}_#{seq}"
    entry_type   = "rental_owed_change_ap"

    revenue     = Accounting.get_account_by_code!(@rental_revenue_code)
    owed_change = Accounting.get_account_by_code!(@owed_change_ap_code)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Owed change — rental ##{rental.id}",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: revenue.id,     debit_cents: overpayment_cents, credit_cents: 0,
          description: "Reverse excess rental revenue — rental ##{rental.id}"},
        %{account_id: owed_change.id, debit_cents: 0, credit_cents: overpayment_cents,
          description: "Owed change payable — rental ##{rental.id}"}
      ]
    )
  end

  @doc """
  When staff physically gives the renter their change, reclassifies the overpayment
  from Rental Revenue to the source cash/bank account.

    DR  Space Rental Revenue (4030)  [change_given_cents]
    CR  {from_account}               [change_given_cents]
  """
  def record_rental_change_given(rental, change_given_cents, from_account_id, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_rental_change_given_#{rental.id}_#{seq}"
    entry_type   = "rental_change_given"

    revenue      = Accounting.get_account_by_code!(@rental_revenue_code)
    from_account = Accounting.get_account!(from_account_id)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: "Change given back — rental ##{rental.id}",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: revenue.id,      debit_cents: change_given_cents, credit_cents: 0,
          description: "Reverse excess rental revenue — rental ##{rental.id}"},
        %{account_id: from_account.id, debit_cents: 0, credit_cents: change_given_cents,
          description: "Change given back to renter — rental ##{rental.id}"}
      ]
    )
  end

  # ── Subscription Refund ───────────────────────────────────────────────

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

  # ── Partner Fee ───────────────────────────────────────────────────────

  @doc """
  Records a manually entered partner fee collected per session or service.

    DR  Cash (1000)                 [amount_cents]
    CR  Partner Fee Revenue (4040)  [amount_cents]

  Options:
    - `:payment_date` — defaults to today
    - `:note`         — optional description override

  Each call creates a unique entry since fees are recorded manually per session.
  """
  def record_partner_fee(partner_id, amount_cents, opts \\ []) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note         = Keyword.get(opts, :note)
    seq          = :erlang.unique_integer([:positive, :monotonic])
    reference    = "vs_partner_fee_#{partner_id}_#{seq}"
    entry_type   = "partner_fee"

    cash    = Accounting.get_account_by_code!(@cash_code)
    revenue = Accounting.get_account_by_code!(@partner_fee_revenue_code)

    Accounting.create_journal_entry_with_lines(
      %{
        date:        payment_date,
        description: note || "Partner fee — partner ##{partner_id}",
        reference:   reference,
        entry_type:  entry_type
      },
      [
        %{account_id: cash.id,    debit_cents: amount_cents, credit_cents: 0,
          description: "Cash received — partner fee, partner ##{partner_id}"},
        %{account_id: revenue.id, debit_cents: 0,            credit_cents: amount_cents,
          description: "Partner fee revenue — partner ##{partner_id}"}
      ]
    )
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp idempotent(reference, entry_type, fun) do
    existing =
      from(je in JournalEntry,
        where: je.reference == ^reference and je.entry_type == ^entry_type
      )
      |> Repo.one()

    if existing, do: {:ok, existing}, else: fun.()
  end
end
