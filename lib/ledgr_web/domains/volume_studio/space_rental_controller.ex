defmodule LedgrWeb.Domains.VolumeStudio.SpaceRentalController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Spaces
  alias Ledgr.Domains.VolumeStudio.Spaces.SpaceRental
  alias Ledgr.Core.Customers
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    status = params["status"]
    rentals = Spaces.list_space_rentals(status: status)
    render(conn, :index, rentals: rentals, current_status: status)
  end

  def show(conn, %{"id" => id}) do
    rental = Spaces.get_space_rental!(id)
    render(conn, :show, rental: rental)
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
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :iva_cents])

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
      "amount_cents" => MoneyHelper.cents_to_pesos(rental.amount_cents),
      "iva_cents" => MoneyHelper.cents_to_pesos(rental.iva_cents || 0)
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
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents, :iva_cents])

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

  def record_payment(conn, %{"id" => id}) do
    rental = Spaces.get_space_rental!(id)

    case Spaces.record_payment(rental) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Payment recorded successfully.")
        |> redirect(to: dp(conn, "/space-rentals/#{id}"))

      {:error, :already_paid} ->
        conn
        |> put_flash(:error, "This rental is already paid.")
        |> redirect(to: dp(conn, "/space-rentals/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Payment failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/space-rentals/#{id}"))
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

  embed_templates "space_rental_html/*"

  def status_class("confirmed"), do: "status-partial"
  def status_class("active"), do: "status-paid"
  def status_class("completed"), do: "status-paid"
  def status_class("cancelled"), do: "status-unpaid"
  def status_class(_), do: ""
end
