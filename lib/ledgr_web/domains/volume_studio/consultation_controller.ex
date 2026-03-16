defmodule LedgrWeb.Domains.VolumeStudio.ConsultationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Consultations
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Instructors
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.{Customers, Accounting}
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    status = params["status"]
    consultations = Consultations.list_consultations(status: status)
    render(conn, :index, consultations: consultations, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)
    payments     = Consultations.list_payments_for_consultation(consultation)
    render(conn, :show, consultation: consultation, payments: payments)
  end

  def new(conn, _params) do
    changeset = Consultations.change_consultation(%Consultation{scheduled_at: DateTime.utc_now()})
    customers = customer_options()
    instructors = Instructors.list_active_instructors()
    render(conn, :new,
      changeset: changeset,
      customers: customers,
      instructors: instructors,
      action: dp(conn, "/consultations")
    )
  end

  def create(conn, %{"consultation" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :iva_cents])

    case Consultations.create_consultation(params) do
      {:ok, c} ->
        conn
        |> put_flash(:info, "Consultation created.")
        |> redirect(to: dp(conn, "/consultations/#{c.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        instructors = Instructors.list_active_instructors()
        render(conn, :new,
          changeset: changeset,
          customers: customers,
          instructors: instructors,
          action: dp(conn, "/consultations")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)
    attrs = %{
      "amount_cents" => MoneyHelper.cents_to_pesos(consultation.amount_cents),
      "iva_cents"    => MoneyHelper.cents_to_pesos(consultation.iva_cents || 0)
    }
    changeset = Consultations.change_consultation(consultation, attrs)
    customers = customer_options()
    instructors = Instructors.list_active_instructors()
    render(conn, :edit,
      consultation: consultation,
      changeset: changeset,
      customers: customers,
      instructors: instructors,
      action: dp(conn, "/consultations/#{id}")
    )
  end

  def update(conn, %{"id" => id, "consultation" => params}) do
    consultation = Consultations.get_consultation!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :iva_cents])

    case Consultations.update_consultation(consultation, params) do
      {:ok, c} ->
        conn
        |> put_flash(:info, "Consultation updated.")
        |> redirect(to: dp(conn, "/consultations/#{c.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        customers = customer_options()
        instructors = Instructors.list_active_instructors()
        render(conn, :edit,
          consultation: consultation,
          changeset: changeset,
          customers: customers,
          instructors: instructors,
          action: dp(conn, "/consultations/#{id}")
        )
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    consultation = Consultations.get_consultation!(id)

    case Consultations.update_status(consultation, status) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Status updated.")
        |> redirect(to: dp(conn, "/consultations/#{id}"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to update status.")
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end

  def new_payment(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)
    summary      = Consultations.payment_summary(consultation)

    summary_rows = [
      %{label: "Amount",      value_cents: summary.amount_cents,      style: :normal},
      %{label: "IVA (16%)",   value_cents: summary.iva_cents,         style: :normal},
      %{label: "Total",       value_cents: summary.total_cents,        style: :total_row},
      %{label: "Outstanding", value_cents: summary.outstanding_cents,
        style: if(summary.outstanding_cents > 0, do: :danger, else: :success)}
    ]

    render(conn, :new_payment,
      consultation:         consultation,
      summary_rows:         summary_rows,
      outstanding_cents:    summary.outstanding_cents,
      default_amount_cents: summary.outstanding_cents,
      change_accounts:      Accounting.cash_or_bank_account_options(),
      paid_to_accounts:     Ledgr.Domains.VolumeStudio.paid_to_account_options(),
      action:               dp(conn, "/consultations/#{id}/payment"),
      back_path:            dp(conn, "/consultations/#{id}")
    )
  end

  def record_payment(conn, %{"id" => id, "payment" => payment_params}) do
    consultation       = Consultations.get_consultation!(id)
    summary            = Consultations.payment_summary(consultation)
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

      case Consultations.record_payment(consultation, amount_cents,
             payment_date: payment_date,
             method: method,
             note: note,
             paid_to_account_code: paid_to_account_code
           ) do
        {:ok, _} ->
          overpayment = max(0, amount_cents - outstanding_before)

          cond do
            owed_change_choice == "record" and overpayment > 0 ->
              fresh = Consultations.get_consultation!(id)
              VolumeStudioAccounting.record_consultation_owed_change_ap(fresh, overpayment,
                payment_date: payment_date
              )

            owed_change_choice == "staff_gave_change" ->
              change_given_str    = Map.get(payment_params, "change_given", "0")
              change_from_account = Map.get(payment_params, "change_from_account", "")

              case Float.parse(change_given_str) do
                {change_float, _} ->
                  change_given_cents = round(change_float * 100)

                  if change_given_cents > 0 and change_from_account != "" do
                    fresh = Consultations.get_consultation!(id)
                    VolumeStudioAccounting.record_consultation_change_given(
                      fresh,
                      change_given_cents,
                      change_from_account,
                      payment_date: payment_date
                    )
                  end

                :error -> :ok
              end

            true -> :ok
          end

          conn
          |> put_flash(:info, "Payment recorded successfully.")
          |> redirect(to: dp(conn, "/consultations/#{id}"))

        {:error, :already_paid} ->
          conn
          |> put_flash(:error, "This consultation is already paid.")
          |> redirect(to: dp(conn, "/consultations/#{id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Payment failed: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/consultations/#{id}/payment/new"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid payment amount or date.")
        |> redirect(to: dp(conn, "/consultations/#{id}/payment/new"))
    end
  end

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.ConsultationHTML do
  use LedgrWeb, :html
  import LedgrWeb.Domains.VolumeStudio.PaymentFormComponent

  embed_templates "consultation_html/*"

  def status_class("scheduled"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class("no_show"),   do: "status-unpaid"
  def status_class(_),           do: ""

  def format_datetime(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%b %-d, %Y · %-I:%M %p")
  def format_datetime(nil), do: "—"
  def format_datetime(other), do: to_string(other)
end
