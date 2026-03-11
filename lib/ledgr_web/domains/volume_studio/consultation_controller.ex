defmodule LedgrWeb.Domains.VolumeStudio.ConsultationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Consultations
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Instructors
  alias Ledgr.Core.Customers
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    status = params["status"]
    consultations = Consultations.list_consultations(status: status)
    render(conn, :index, consultations: consultations, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)
    render(conn, :show, consultation: consultation)
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
      "iva_cents" => MoneyHelper.cents_to_pesos(consultation.iva_cents || 0)
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

  def record_payment(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)

    case Consultations.record_payment(consultation) do
      {:ok, _} ->
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
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.ConsultationHTML do
  use LedgrWeb, :html

  embed_templates "consultation_html/*"

  def status_class("scheduled"), do: "status-partial"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class("no_show"), do: "status-unpaid"
  def status_class(_), do: ""
end
