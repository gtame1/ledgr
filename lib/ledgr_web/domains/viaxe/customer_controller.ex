defmodule LedgrWeb.Domains.Viaxe.CustomerController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Customers
  alias Ledgr.Domains.Viaxe.Customers.{Customer, CustomerTravelProfile}
  alias Ledgr.Domains.Viaxe.TravelDocuments

  def index(conn, _params) do
    customers = Customers.list_customers()
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    travel_profile = Customers.get_or_build_travel_profile(customer)

    passport_changeset =
      TravelDocuments.change_passport(%Ledgr.Domains.Viaxe.TravelDocuments.Passport{
        customer_id: customer.id
      })

    visa_changeset =
      TravelDocuments.change_visa(%Ledgr.Domains.Viaxe.TravelDocuments.Visa{
        customer_id: customer.id
      })

    loyalty_changeset =
      TravelDocuments.change_loyalty_program(%Ledgr.Domains.Viaxe.TravelDocuments.LoyaltyProgram{
        customer_id: customer.id
      })

    render(conn, :show,
      customer: customer,
      travel_profile: travel_profile,
      passport_changeset: passport_changeset,
      visa_changeset: visa_changeset,
      loyalty_changeset: loyalty_changeset
    )
  end

  def new(conn, _params) do
    changeset = Customers.change_customer(%Customer{})
    profile_changeset = Customers.change_travel_profile(%CustomerTravelProfile{})

    render(conn, :new,
      changeset: changeset,
      profile_changeset: profile_changeset,
      action: dp(conn, "/customers")
    )
  end

  def create(conn, %{"customer" => customer_params}) do
    {profile_params, customer_params} = Map.pop(customer_params, "travel_profile", %{})

    case Customers.create_customer(customer_params) do
      {:ok, customer} ->
        if map_size(profile_params) > 0 do
          Customers.upsert_travel_profile(customer, profile_params)
        end

        conn
        |> put_flash(:info, "Customer created successfully.")
        |> redirect(to: dp(conn, "/customers/#{customer.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        profile_changeset = Customers.change_travel_profile(%CustomerTravelProfile{})

        render(conn, :new,
          changeset: changeset,
          profile_changeset: profile_changeset,
          action: dp(conn, "/customers")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    changeset = Customers.change_customer(customer)
    travel_profile = Customers.get_or_build_travel_profile(customer)
    profile_changeset = Customers.change_travel_profile(travel_profile)

    passport_changeset =
      TravelDocuments.change_passport(%Ledgr.Domains.Viaxe.TravelDocuments.Passport{
        customer_id: customer.id
      })

    visa_changeset =
      TravelDocuments.change_visa(%Ledgr.Domains.Viaxe.TravelDocuments.Visa{
        customer_id: customer.id
      })

    loyalty_changeset =
      TravelDocuments.change_loyalty_program(%Ledgr.Domains.Viaxe.TravelDocuments.LoyaltyProgram{
        customer_id: customer.id
      })

    render(conn, :edit,
      customer: customer,
      changeset: changeset,
      travel_profile: travel_profile,
      profile_changeset: profile_changeset,
      passport_changeset: passport_changeset,
      visa_changeset: visa_changeset,
      loyalty_changeset: loyalty_changeset,
      action: dp(conn, "/customers/#{id}")
    )
  end

  def update(conn, %{"id" => id, "customer" => customer_params}) do
    customer = Customers.get_customer!(id)
    {profile_params, customer_params} = Map.pop(customer_params, "travel_profile", %{})

    case Customers.update_customer(customer, customer_params) do
      {:ok, customer} ->
        if map_size(profile_params) > 0 do
          Customers.upsert_travel_profile(customer, profile_params)
        end

        conn
        |> put_flash(:info, "Customer updated successfully.")
        |> redirect(to: dp(conn, "/customers/#{customer.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        travel_profile = Customers.get_or_build_travel_profile(customer)
        profile_changeset = Customers.change_travel_profile(travel_profile)

        passport_changeset =
          TravelDocuments.change_passport(%Ledgr.Domains.Viaxe.TravelDocuments.Passport{
            customer_id: customer.id
          })

        visa_changeset =
          TravelDocuments.change_visa(%Ledgr.Domains.Viaxe.TravelDocuments.Visa{
            customer_id: customer.id
          })

        loyalty_changeset =
          TravelDocuments.change_loyalty_program(
            %Ledgr.Domains.Viaxe.TravelDocuments.LoyaltyProgram{customer_id: customer.id}
          )

        render(conn, :edit,
          customer: customer,
          changeset: changeset,
          travel_profile: travel_profile,
          profile_changeset: profile_changeset,
          passport_changeset: passport_changeset,
          visa_changeset: visa_changeset,
          loyalty_changeset: loyalty_changeset,
          action: dp(conn, "/customers/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)
    {:ok, _} = Customers.delete_customer(customer)

    conn
    |> put_flash(:info, "Customer deleted successfully.")
    |> redirect(to: dp(conn, "/customers"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.CustomerHTML do
  use LedgrWeb, :html

  alias Ledgr.Domains.Viaxe.Customers.Customer

  embed_templates "customer_html/*"

  def full_name(customer), do: Customer.full_name(customer)
end
