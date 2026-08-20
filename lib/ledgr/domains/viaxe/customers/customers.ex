defmodule Ledgr.Domains.Viaxe.Customers do
  @moduledoc """
  Context for Viaxe-specific customer management.

  Uses the Viaxe Customer schema (split name fields + travel profile associations)
  rather than the shared core Customer schema.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Customers.{Customer, CustomerTravelProfile}

  def list_customers do
    Customer
    |> order_by([:last_name, :first_name])
    |> Repo.all()
  end

  def get_customer!(id) do
    Customer
    |> preload([:travel_profile, :passports, :visas, :loyalty_programs])
    |> Repo.get!(id)
  end

  def create_customer(attrs \\ %{}) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  def customer_select_options do
    Customer
    |> order_by([:last_name, :first_name])
    |> Repo.all()
    |> Enum.map(fn c -> {Customer.full_name(c), c.id} end)
  end

  # ── Travel Profile ─────────────────────────────────────────────────

  def get_or_build_travel_profile(%Customer{id: customer_id}) do
    case Repo.get_by(CustomerTravelProfile, customer_id: customer_id) do
      nil -> %CustomerTravelProfile{customer_id: customer_id}
      profile -> profile
    end
  end

  def upsert_travel_profile(%Customer{} = customer, attrs) do
    profile = get_or_build_travel_profile(customer)

    profile
    |> CustomerTravelProfile.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def change_travel_profile(%CustomerTravelProfile{} = profile, attrs \\ %{}) do
    CustomerTravelProfile.changeset(profile, attrs)
  end
end
