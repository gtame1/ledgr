defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Subscriptions
  alias Ledgr.Domains.VolumeStudio.Subscriptions.Subscription
  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Domains.VolumeStudio.ClassSessions
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Customers
  alias Ledgr.Core.Customers.Customer

  def index(conn, params) do
    current_plan_type = params["plan_type"]
    db_plan_type = if current_plan_type in ["membership", "package", "promo", "extra"],
      do: current_plan_type, else: nil
    status = if current_plan_type, do: nil, else: params["status"]

    subscriptions = Subscriptions.list_subscriptions(status: status, plan_type: db_plan_type)
    render(conn, :index,
      subscriptions: subscriptions,
      current_status: status,
      current_plan_type: current_plan_type
    )
  end

  def show(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    subscription = maybe_auto_expire(subscription)
    summary      = Subscriptions.payment_summary(subscription)
    payments     = Subscriptions.list_payments_for_subscription(subscription)
    bookings     = Subscriptions.list_bookings_for_subscription(subscription)
    render(conn, :show,
      subscription: subscription,
      summary:      summary,
      payments:     payments,
      bookings:     bookings
    )
  end

  defp maybe_auto_expire(%{status: status} = sub) when status in ["active", "paused"] do
    plan      = sub.subscription_plan
    today     = today_mx()
    past_due  = sub.ends_on && Date.compare(sub.ends_on, today) == :lt
    maxed_out = plan.class_limit && sub.classes_used >= plan.class_limit

    new_status =
      cond do
        maxed_out -> "completed"
        past_due  -> "expired"
        true      -> nil
      end

    if new_status do
      case Subscriptions.finalize(sub, new_status) do
        {:ok, updated} -> updated
        _              -> sub
      end
    else
      sub
    end
  end

  defp maybe_auto_expire(sub), do: sub

  def new(conn, params) do
    mode = Map.get(params, "mode", "existing")
    preselected_customer_id = params["customer_id"]

    changeset =
      if preselected_customer_id do
        Subscriptions.change_subscription(%Subscription{}, %{
          "customer_id" => preselected_customer_id,
          "starts_on"   => today_mx()
        })
      else
        Subscriptions.change_subscription(%Subscription{starts_on: today_mx()})
      end

    customer_changeset = Customers.change_customer(%Customer{})
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :new,
      changeset:               changeset,
      customer_changeset:      customer_changeset,
      customers:               customers,
      plans:                   plans,
      mode:                    mode,
      preselected_customer_id: preselected_customer_id,
      action:                  dp(conn, "/subscriptions")
    )
  end

  def create(conn, %{"subscription" => params}) do
    mode = Map.get(params, "mode", "existing")
    new_customer_params = Map.get(params, "new_customer", %{})
    sub_params = Map.drop(params, ["mode", "new_customer"])

    result =
      if mode == "new" do
        case Customers.create_customer(new_customer_params) do
          {:ok, customer} ->
            Subscriptions.create_subscription(Map.put(sub_params, "customer_id", customer.id))
          {:error, customer_changeset} ->
            {:error, :customer, customer_changeset}
        end
      else
        Subscriptions.create_subscription(sub_params)
      end

    case result do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription created successfully.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, :customer, customer_changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: Subscriptions.change_subscription(%Subscription{}),
          customer_changeset: customer_changeset,
          customers: customers,
          plans: plans,
          mode: "new",
          action: dp(conn, "/subscriptions")
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :new,
          changeset: changeset,
          customer_changeset: Customers.change_customer(%Customer{}),
          customers: customers,
          plans: plans,
          mode: mode,
          action: dp(conn, "/subscriptions")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    changeset = Subscriptions.change_subscription(subscription)
    customers = customer_options()
    plans = SubscriptionPlans.list_active_subscription_plans()
    render(conn, :edit,
      subscription: subscription,
      changeset: changeset,
      customers: customers,
      plans: plans,
      action: dp(conn, "/subscriptions/#{id}")
    )
  end

  def update(conn, %{"id" => id, "subscription" => params}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.update_subscription(subscription, params) do
      {:ok, sub} ->
        conn
        |> put_flash(:info, "Subscription updated.")
        |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        plans = SubscriptionPlans.list_active_subscription_plans()
        render(conn, :edit,
          subscription: subscription,
          changeset: changeset,
          customers: customers,
          plans: plans,
          action: dp(conn, "/subscriptions/#{id}")
        )
    end
  end

  def new_booking(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    sessions =
      ClassSessions.list_class_sessions(status: "scheduled")
      |> Enum.reverse()
    render(conn, :new_booking,
      subscription: subscription,
      sessions:     sessions,
      action:       dp(conn, "/subscriptions/#{id}/bookings")
    )
  end

  def create_booking(conn, %{"id" => id, "booking" => params}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.get_soonest_expiring_subscription(subscription.customer_id) do
      nil ->
        conn
        |> put_flash(:error, "No active subscription with available classes found for this member.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      target_sub ->
        attrs = %{
          class_session_id: params["class_session_id"],
          customer_id:      subscription.customer_id,
          subscription_id:  target_sub.id,
          status:           "booked"
        }

        case ClassSessions.create_booking(attrs) do
          {:ok, _booking} ->
            conn
            |> put_flash(:info, "Booking created and counted under \"#{target_sub.subscription_plan.name}\" (expires #{target_sub.ends_on}).")
            |> redirect(to: dp(conn, "/subscriptions/#{id}"))

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not create booking. The member may already be booked for this session.")
            |> redirect(to: dp(conn, "/subscriptions/#{id}/bookings/new"))
        end
    end
  end

  def new_payment(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    summary      = Subscriptions.payment_summary(subscription)
    plan         = subscription.subscription_plan

    discount_rows =
      if summary.discount_cents > 0 do
        [
          %{label: "Discount",  value_cents: summary.discount_cents, style: :discount},
          %{label: "Subtotal",  value_cents: summary.effective_price, style: :normal}
        ]
      else
        []
      end

    totals_row =
      if summary.discount_cents > 0 or summary.iva_cents > 0 do
        [%{label: "Total", value_cents: summary.total_cents, style: :total_row}]
      else
        []
      end

    summary_rows =
      [%{label: "Plan Price", value_cents: plan.price_cents, style: :normal}] ++
      discount_rows ++
      [%{label: "IVA (16%)", value_cents: summary.iva_cents, style: :normal}] ++
      totals_row ++
      [
        %{label: "Already Paid",  value_cents: summary.total_paid, style: :normal},
        %{label: "Outstanding",   value_cents: summary.outstanding_cents,
          style: if(summary.outstanding_cents > 0, do: :danger, else: :success)}
      ]

    render(conn, :new_payment,
      subscription:        subscription,
      summary_rows:        summary_rows,
      outstanding_cents:   summary.outstanding_cents,
      default_amount_cents: summary.outstanding_cents,
      change_accounts:     Accounting.cash_or_bank_account_options(),
      paid_to_accounts:    Ledgr.Domains.VolumeStudio.paid_to_account_options(),
      action:              dp(conn, "/subscriptions/#{id}/payment"),
      back_path:           dp(conn, "/subscriptions/#{id}")
    )
  end

  def record_payment(conn, %{"id" => id, "payment" => payment_params}) do
    subscription       = Subscriptions.get_subscription!(id)
    summary            = Subscriptions.payment_summary(subscription)
    outstanding_before = summary.outstanding_cents
    amount_str         = Map.get(payment_params, "amount", "")
    method             = Map.get(payment_params, "method")
    note               = Map.get(payment_params, "note")
    date_str           = Map.get(payment_params, "payment_date", "")
    owed_change_choice = Map.get(payment_params, "owed_change_choice", "keep")
    paid_to_account_code = Map.get(payment_params, "paid_to_account_code", "1000")

    with {amount_float, _} <- Float.parse(amount_str),
         amount_cents = round(amount_float * 100),
         true <- amount_cents > 0,
         {:ok, payment_date} <- Date.from_iso8601(date_str) do
      opts = [method: method, note: note, payment_date: payment_date,
              paid_to_account_code: paid_to_account_code]

      case Subscriptions.record_payment(subscription, amount_cents, opts) do
        {:ok, _} ->
          overpayment = max(0, amount_cents - outstanding_before)

          cond do
            owed_change_choice == "record" and overpayment > 0 ->
              fresh_sub = Subscriptions.get_subscription!(id)
              VolumeStudioAccounting.record_owed_change_ap(fresh_sub, overpayment,
                payment_date: payment_date
              )

            owed_change_choice == "staff_gave_change" ->
              change_given_str    = Map.get(payment_params, "change_given", "0")
              change_from_account = Map.get(payment_params, "change_from_account", "")

              case Float.parse(change_given_str) do
                {change_float, _} ->
                  change_given_cents = round(change_float * 100)

                  if change_given_cents > 0 and change_from_account != "" do
                    fresh_sub = Subscriptions.get_subscription!(id)
                    VolumeStudioAccounting.record_change_given(
                      fresh_sub,
                      change_given_cents,
                      change_from_account,
                      payment_date: payment_date
                    )
                  end

                :error ->
                  :ok
              end

            true ->
              :ok
          end

          conn
          |> put_flash(:info, "Payment of $#{amount_str} MXN recorded successfully.")
          |> redirect(to: dp(conn, "/subscriptions/#{id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not record payment: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/new"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid amount or date. Please check the form.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/new"))
    end
  end

  def edit_payment(conn, %{"id" => id, "entry_id" => entry_id}) do
    subscription = Subscriptions.get_subscription!(id)
    entry        = Accounting.get_journal_entry!(entry_id)

    # Pull amount from the debit (Cash DR) line
    amount_cents =
      entry.journal_lines
      |> Enum.find(&(&1.debit_cents > 0))
      |> case do
        nil -> 0
        line -> line.debit_cents
      end

    render(conn, :edit_payment,
      subscription:  subscription,
      entry:         entry,
      amount_cents:  amount_cents,
      action:        dp(conn, "/subscriptions/#{id}/payment/#{entry_id}")
    )
  end

  def update_payment(conn, %{"id" => id, "entry_id" => entry_id, "payment" => params}) do
    subscription     = Subscriptions.get_subscription!(id)
    entry            = Accounting.get_journal_entry!(entry_id)
    amount_str       = Map.get(params, "amount", "")
    date_str         = Map.get(params, "payment_date", "")
    note             = Map.get(params, "note")

    with {amount_float, _} <- Float.parse(amount_str),
         amount_cents = round(amount_float * 100),
         true <- amount_cents > 0,
         {:ok, payment_date} <- Date.from_iso8601(date_str) do
      case Subscriptions.update_payment(subscription, entry, %{
        amount_cents: amount_cents,
        payment_date: payment_date,
        note:         note
      }) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Payment updated successfully.")
          |> redirect(to: dp(conn, "/subscriptions/#{id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Could not update payment: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/#{entry_id}/edit"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid amount or date.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}/payment/#{entry_id}/edit"))
    end
  end

  def delete_payment(conn, %{"id" => id, "entry_id" => entry_id}) do
    subscription = Subscriptions.get_subscription!(id)
    entry        = Accounting.get_journal_entry!(entry_id)

    case Subscriptions.delete_payment(subscription, entry) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Payment deleted.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not delete payment: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    subscription = Subscriptions.get_subscription!(id)

    result =
      case status do
        s when s in ["completed", "expired"] ->
          Subscriptions.finalize(subscription, s)
        "cancelled" ->
          Subscriptions.cancel(subscription)
        _ ->
          Subscriptions.update_subscription(subscription, %{status: status})
      end

    case result do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Subscription marked as #{status}.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not update subscription status.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  def redeem(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)

    case Subscriptions.redeem_extra(subscription) do
      {:ok, _} ->
        had_deferred = subscription.deferred_revenue_cents > 0
        msg = if had_deferred,
          do: "Marked as used — revenue recognized.",
          else: "Marked as used. Revenue will be recognized once payment is recorded."
        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not mark as used: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  def new_reactivate(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    render(conn, :reactivate,
      subscription: subscription,
      action:       dp(conn, "/subscriptions/#{id}/reactivate"),
      back_path:    dp(conn, "/subscriptions/#{id}")
    )
  end

  def reactivate(conn, %{"id" => id, "subscription" => params}) do
    subscription = Subscriptions.get_subscription!(id)
    ends_on_str  = Map.get(params, "ends_on", "")

    case Date.from_iso8601(ends_on_str) do
      {:ok, ends_on} ->
        case Subscriptions.update_subscription(subscription, %{status: "active", ends_on: ends_on}) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Subscription reactivated through #{ends_on}.")
            |> redirect(to: dp(conn, "/subscriptions/#{id}"))

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not reactivate subscription.")
            |> redirect(to: dp(conn, "/subscriptions/#{id}/reactivate"))
        end

      :error ->
        conn
        |> put_flash(:error, "Invalid date. Please select a valid expiration date.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}/reactivate"))
    end
  end

  def new_cancel(conn, %{"id" => id}) do
    subscription = Subscriptions.get_subscription!(id)
    summary      = Subscriptions.payment_summary(subscription)
    accounts     = Accounting.cash_or_bank_account_options()

    render(conn, :cancel,
      subscription: subscription,
      summary:      summary,
      accounts:     accounts,
      action:       dp(conn, "/subscriptions/#{id}/cancel")
    )
  end

  def cancel(conn, %{"id" => id} = params) do
    subscription = Subscriptions.get_subscription!(id)
    summary      = Subscriptions.payment_summary(subscription)

    refund_params = params["refund"] || %{}
    raw_amount    = refund_params["amount"] || "0"
    refund_cents  =
      case Float.parse(raw_amount) do
        {v, _} -> round(v * 100)
        :error  -> 0
      end
    account_id = refund_params["account_id"]
    note       = refund_params["note"]

    with :ok <- validate_refund(refund_cents, summary.total_paid),
         {:ok, _} <- maybe_record_refund(subscription, refund_cents, account_id, note),
         {:ok, _} <- Subscriptions.cancel(subscription) do
      msg = if refund_cents > 0, do: "Subscription cancelled and refund recorded.", else: "Subscription cancelled."
      conn
      |> put_flash(:info, msg)
      |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    else
      {:error, :invalid_refund} ->
        conn
        |> put_flash(:error, "Refund amount exceeds total paid ($#{:erlang.float_to_binary(summary.total_paid / 100, [{:decimals, 2}])} MXN).")
        |> redirect(to: dp(conn, "/subscriptions/#{id}/cancel"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not cancel subscription.")
        |> redirect(to: dp(conn, "/subscriptions/#{id}"))
    end
  end

  defp validate_refund(cents, total_paid) when cents <= total_paid, do: :ok
  defp validate_refund(_, _), do: {:error, :invalid_refund}

  defp maybe_record_refund(_sub, 0, _account_id, _note), do: {:ok, nil}
  defp maybe_record_refund(_sub, _cents, nil, _note), do: {:ok, nil}
  defp maybe_record_refund(_sub, _cents, "", _note), do: {:ok, nil}
  defp maybe_record_refund(sub, refund_cents, account_id, note) do
    case VolumeStudioAccounting.record_subscription_refund(sub, refund_cents, account_id, today_mx(), note) do
      {:ok, _entry} -> Subscriptions.apply_refund(sub, refund_cents)
      err           -> err
    end
  end

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SubscriptionHTML do
  use LedgrWeb, :html
  import LedgrWeb.Domains.VolumeStudio.PaymentFormComponent

  embed_templates "subscription_html/*"

  def status_class("active"),    do: "status-paid"
  def status_class("paused"),    do: "status-partial"
  def status_class("completed"), do: "status-extra"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class("expired"),   do: "status-unpaid"
  def status_class(_),           do: ""

  def plan_label(plan) do
    price =
      if rem(plan.price_cents, 100) == 0 do
        "$#{div(plan.price_cents, 100)}"
      else
        "$#{Float.round(plan.price_cents / 100, 2)}"
      end
    "#{plan.name} — #{price} MXN"
  end

  def plan_type_badge("package"),    do: "status-partial"
  def plan_type_badge("promo"),      do: "status-promo"
  def plan_type_badge("membership"), do: "status-paid"
  def plan_type_badge("extra"),      do: "status-extra"
  def plan_type_badge(_),            do: ""

  def booking_status_class("checked_in"), do: "status-paid"
  def booking_status_class("booked"), do: "status-partial"
  def booking_status_class("cancelled"), do: "status-unpaid"
  def booking_status_class("no_show"), do: "status-unpaid"
  def booking_status_class(_), do: ""

  @doc "Returns {label, css_class} for the payment status badge shown in the subscriptions list."
  def payment_status(sub) do
    plan  = sub.subscription_plan
    base  = max(plan.price_cents - (sub.discount_cents || 0), 0)
    total = base + (sub.iva_cents || 0)
    paid  = sub.paid_cents || 0

    cond do
      total == 0    -> {"Paid", "status-paid"}
      paid >= total -> {"Paid", "status-paid"}
      paid > 0      -> {"Partial", "status-partial"}
      true          -> {"Unpaid", "status-unpaid"}
    end
  end
end
