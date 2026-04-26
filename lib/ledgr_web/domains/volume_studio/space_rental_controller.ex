defmodule LedgrWeb.Domains.VolumeStudio.SpaceRentalController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Spaces
  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Customers
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    status = params["status"]
    rentals = Spaces.list_space_rentals(status: status)
    render(conn, :index, rentals: rentals, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    rental   = Spaces.get_space_rental!(id)
    summary  = Spaces.payment_summary(rental)
    payments = Spaces.list_rental_payments(rental)
    render(conn, :show, rental: rental, summary: summary, payments: payments)
  end

  def new(conn, _params) do
    changeset = Spaces.change_space_rental(%SpaceRental{})
    spaces = Spaces.list_active_spaces()
    customers = customer_options()
    render(conn, :new,
      changeset: changeset,
      spaces: spaces,
      customers: customers,
      action: dp(conn, "/space-rentals")
    )
  end

  def create(conn, %{"space_rental" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :discount_cents])

    case Spaces.create_space_rental(params) do
      {:ok, rental} ->
        conn
        |> put_flash(:info, "Space rental created.")
        |> redirect(to: dp(conn, "/space-rentals/#{rental.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        spaces = Spaces.list_active_spaces()
        customers = customer_options()
        render(conn, :new,
          changeset: changeset,
          spaces: spaces,
          customers: customers,
          action: dp(conn, "/space-rentals")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    rental = Spaces.get_space_rental!(id)
    attrs = %{
      "amount_cents"   => MoneyHelper.cents_to_pesos(rental.amount_cents),
      "discount_cents" => MoneyHelper.cents_to_pesos(rental.discount_cents || 0)
    }
    changeset = Spaces.change_space_rental(rental, attrs)
    spaces = Spaces.list_active_spaces()
    customers = customer_options()
    render(conn, :edit,
      rental: rental,
      changeset: changeset,
      spaces: spaces,
      customers: customers,
      action: dp(conn, "/space-rentals/#{id}")
    )
  end

  def update(conn, %{"id" => id, "space_rental" => params}) do
    rental = Spaces.get_space_rental!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :discount_cents])

    case Spaces.update_space_rental(rental, params) do
      {:ok, rental} ->
        conn
        |> put_flash(:info, "Space rental updated.")
        |> redirect(to: dp(conn, "/space-rentals/#{rental.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        spaces = Spaces.list_active_spaces()
        customers = customer_options()
        render(conn, :edit,
          rental: rental,
          changeset: changeset,
          spaces: spaces,
          customers: customers,
          action: dp(conn, "/space-rentals/#{id}")
        )
    end
  end

  def new_payment(conn, %{"id" => id}) do
    rental  = Spaces.get_space_rental!(id)
    summary = Spaces.payment_summary(rental)

    total_label = if summary.discount_cents > 0, do: "Effective Total", else: "Total Due"

    discount_rows =
      if summary.discount_cents > 0 do
        [%{label: "Discount", value_cents: summary.discount_cents, style: :discount}]
      else
        []
      end

    fmt_dt = fn
      nil -> "—"
      %DateTime{} = dt -> fmt_datetime(dt, "%b %-d, %Y · %-I:%M %p")
      %NaiveDateTime{} = ndt -> fmt_datetime(ndt, "%b %-d, %Y · %-I:%M %p")
      other -> to_string(other)
    end

    period_rows =
      if rental.starts_at || rental.ends_at do
        [%{
          label: "Period",
          value_cents: nil,
          style: :muted,
          text: "#{fmt_dt.(rental.starts_at)} → #{fmt_dt.(rental.ends_at)}"
        }]
      else
        []
      end

    summary_rows =
      [
        %{label: "Base Amount", value_cents: summary.base_cents, style: :normal},
        %{label: "IVA (16%)",   value_cents: summary.iva_cents,  style: :normal}
      ] ++
      discount_rows ++
      [%{label: total_label, value_cents: summary.total_cents, style: :total_row}] ++
      [
        %{label: "Already Paid", value_cents: summary.paid_cents,        style: :normal},
        %{label: "Outstanding",  value_cents: summary.outstanding_cents,
          style: if(summary.outstanding_cents > 0, do: :danger, else: :success)}
      ] ++
      period_rows

    render(conn, :new_payment,
      rental:              rental,
      summary_rows:        summary_rows,
      outstanding_cents:   summary.outstanding_cents,
      default_amount_cents: summary.outstanding_cents,
      change_accounts:     Accounting.cash_or_bank_account_options(),
      paid_to_accounts:    Ledgr.Domains.VolumeStudio.paid_to_account_options(),
      action:              dp(conn, "/space-rentals/#{id}/payment"),
      back_path:           dp(conn, "/space-rentals/#{id}")
    )
  end

  def record_payment(conn, %{"id" => id, "payment" => payment_params}) do
    rental             = Spaces.get_space_rental!(id)
    summary            = Spaces.payment_summary(rental)
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

      attrs = %{
        amount_cents:        amount_cents,
        payment_date:        payment_date,
        method:              method,
        note:                note,
        paid_to_account_code: paid_to_account_code
      }

      case Spaces.record_payment(rental, attrs) do
        {:ok, _} ->
          overpayment = max(0, amount_cents - outstanding_before)

          cond do
            owed_change_choice == "record" and overpayment > 0 ->
              fresh_rental = Spaces.get_space_rental!(id)
              VolumeStudioAccounting.record_rental_owed_change_ap(fresh_rental, overpayment,
                payment_date: payment_date
              )

            owed_change_choice == "staff_gave_change" ->
              change_given_str    = Map.get(payment_params, "change_given", "0")
              change_from_account = Map.get(payment_params, "change_from_account", "")

              case Float.parse(change_given_str) do
                {change_float, _} ->
                  change_given_cents = round(change_float * 100)

                  if change_given_cents > 0 and change_from_account != "" do
                    fresh_rental = Spaces.get_space_rental!(id)
                    VolumeStudioAccounting.record_rental_change_given(
                      fresh_rental,
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
          |> redirect(to: dp(conn, "/space-rentals/#{id}"))

        {:error, reason} ->
          conn
          |> put_flash(:error, "Payment failed: #{inspect(reason)}")
          |> redirect(to: dp(conn, "/space-rentals/#{id}/payment/new"))
      end
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid payment amount or date.")
        |> redirect(to: dp(conn, "/space-rentals/#{id}/payment/new"))
    end
  end

  defp customer_options do
    [{"— No customer —", nil}] ++
      (Customers.list_customers()
       |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id}))
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SpaceRentalHTML do
  use LedgrWeb, :html
  import LedgrWeb.Domains.VolumeStudio.PaymentFormComponent

  embed_templates "space_rental_html/*"

  def status_class("confirmed"), do: "status-partial"
  def status_class("active"), do: "status-paid"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class(_), do: ""

  # Full datetime: "Mar 13, 2026 · 7:57 PM" (Mexico City time)
  def format_datetime(nil), do: "—"
  def format_datetime(%DateTime{} = dt), do: fmt_datetime(dt, "%b %-d, %Y · %-I:%M %p")
  def format_datetime(%NaiveDateTime{} = ndt), do: fmt_datetime(ndt, "%b %-d, %Y · %-I:%M %p")
  def format_datetime(other), do: to_string(other)

  # Date only: "Mar 13, 2026" — for compact table displays
  def format_date(nil), do: "—"
  def format_date(%Date{} = d), do: fmt_date(d, "%b %-d, %Y")
  def format_date(%DateTime{} = dt), do: fmt_date(dt, "%b %-d, %Y")
  def format_date(%NaiveDateTime{} = ndt), do: fmt_date(ndt, "%b %-d, %Y")
  def format_date(other), do: to_string(other)
end
