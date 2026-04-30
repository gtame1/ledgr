defmodule Ledgr.Domains.AumentaMiPension.Customers do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Customers.Customer
  alias Ledgr.Domains.AumentaMiPension.CustomerDeletions.CustomerDeletion

  @doc """
  Lists customers, hiding soft-deleted ones by default. Pass
  `include_deleted: true` or `only_deleted: true` to override.
  """
  def list_customers(opts \\ []) do
    Customer
    |> maybe_search(opts[:search])
    |> filter_deleted(opts)
    |> order_by(desc: :created_at)
    |> Repo.all()
  end

  defp filter_deleted(query, opts) do
    cond do
      opts[:only_deleted] ->
        from c in query,
          join: d in CustomerDeletion,
          on: d.customer_id == c.id

      opts[:include_deleted] ->
        query

      true ->
        from c in query,
          left_join: d in CustomerDeletion,
          on: d.customer_id == c.id,
          where: is_nil(d.customer_id)
    end
  end

  @doc """
  Fetches a customer by id. Soft-deleted customers are still returned (so the
  show page can display the "deleted" banner + restore button).
  """
  def get_customer!(id) do
    Customer
    |> Repo.get!(id)
    |> Repo.preload(consultations: [:agent], pension_cases: [])
  end

  def count_new(start_date, end_date) do
    Customer
    |> where(
      [c],
      fragment("?::date", c.created_at) >= ^start_date and
        fragment("?::date", c.created_at) <= ^end_date
    )
    |> Repo.aggregate(:count)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    where(
      query,
      [c],
      ilike(c.full_name, ^term) or ilike(c.display_name, ^term) or ilike(c.phone, ^term) or
        ilike(c.curp, ^term) or ilike(c.nss, ^term)
    )
  end

  # ── Soft-delete (tombstones) ────────────────────────────────────────────

  @doc """
  Returns the deletion tombstone for a customer, or nil if not deleted.
  """
  def get_deletion(customer_id) do
    Repo.get(CustomerDeletion, customer_id)
  end

  @doc """
  Returns true if the customer has a tombstone row.
  """
  def deleted?(%Customer{id: id}), do: not is_nil(get_deletion(id))
  def deleted?(id) when is_binary(id), do: not is_nil(get_deletion(id))

  @doc """
  Soft-deletes a customer by inserting a tombstone row. Upstream tables
  (`customers`, `conversations`, `messages`, etc.) are left untouched — the
  Ledgr UI filters them out via `list_customers/1`.

  `attrs` may include `:reason` and `:deleted_by` for the audit trail.
  Returns `{:ok, %CustomerDeletion{}}` or `{:error, changeset}`.
  """
  def soft_delete_customer(%Customer{} = customer, attrs \\ %{}) do
    deletion_attrs = %{
      customer_id: customer.id,
      phone: customer.phone,
      full_name: customer.full_name || customer.display_name,
      reason: attrs[:reason],
      deleted_by: attrs[:deleted_by],
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %CustomerDeletion{}
    |> CustomerDeletion.changeset(deletion_attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:reason, :deleted_by, :deleted_at, :updated_at]},
      conflict_target: :customer_id
    )
  end

  @doc """
  Restores a soft-deleted customer by removing the tombstone row.
  """
  def restore_customer(customer_id) when is_binary(customer_id) do
    case Repo.get(CustomerDeletion, customer_id) do
      nil -> {:ok, :not_deleted}
      deletion -> Repo.delete(deletion)
    end
  end
end
