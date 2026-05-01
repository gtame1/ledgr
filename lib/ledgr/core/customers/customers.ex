defmodule Ledgr.Core.Customers do
  @moduledoc """
  The Customers context.
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Core.Customers.Customer

  @doc """
  Returns the list of non-deleted customers, ordered by name.
  """
  def list_customers do
    Customer
    |> where([c], is_nil(c.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  Gets a single non-deleted customer. Raises `Ecto.NoResultsError` if not found or deleted.
  """
  def get_customer!(id) do
    from(c in Customer, where: c.id == ^id and is_nil(c.deleted_at))
    |> Repo.one!()
  end

  @doc """
  Gets a single non-deleted customer by phone number. Returns nil if not found or deleted.
  """
  def get_customer_by_phone(phone) do
    from(c in Customer, where: c.phone == ^phone and is_nil(c.deleted_at))
    |> Repo.one()
  end

  @doc """
  Creates a customer.
  """
  def create_customer(attrs) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a customer.
  """
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a customer.

  If the current domain signals active dependencies (e.g. unpaid orders), returns
  {:error, :has_active_orders} without deleting.

  Otherwise sets deleted_at on the customer and cascades the soft-delete to all
  domain-specific records via the optional on_customer_soft_delete/2 callback.
  """
  def delete_customer(%Customer{} = customer) do
    domain = Ledgr.Domain.current()

    has_deps =
      if domain do
        domain.has_active_dependencies?(customer.id)
      else
        false
      end

    if has_deps do
      {:error, :has_active_orders}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        if domain && function_exported?(domain, :on_customer_soft_delete, 2) do
          domain.on_customer_soft_delete(customer.id, now)
        end

        customer
        |> Ecto.Changeset.change(deleted_at: now)
        |> Repo.update!()
      end)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.
  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  @doc """
  Finds a non-deleted customer by phone number, or creates a new one if not found.
  """
  def find_or_create_by_phone(phone, attrs \\ %{}) do
    case get_customer_by_phone(phone) do
      nil ->
        create_customer(Map.merge(%{phone: phone}, attrs))

      customer ->
        delivery_address = Map.get(attrs, :delivery_address) || Map.get(attrs, "delivery_address")

        if delivery_address && String.trim(delivery_address) != "" do
          case update_customer(customer, %{delivery_address: delivery_address}) do
            {:ok, updated_customer} -> {:ok, updated_customer}
            {:error, _changeset} -> {:ok, customer}
          end
        else
          {:ok, customer}
        end
    end
  end

  @doc """
  Returns a list of customer options for select dropdowns (non-deleted only).
  Format: [{name (phone), id}]
  """
  def customer_select_options do
    list_customers()
    |> Enum.map(fn customer ->
      label =
        if customer.email && customer.email != "" do
          "#{customer.name} (#{customer.phone}) - #{customer.email}"
        else
          "#{customer.name} (#{customer.phone})"
        end

      {label, customer.id}
    end)
  end
end
