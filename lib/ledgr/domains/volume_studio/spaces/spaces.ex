defmodule Ledgr.Domains.VolumeStudio.Spaces do
  @moduledoc """
  Context module for managing Volume Studio spaces and space rentals.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Spaces.{Space, SpaceRental}
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  # ── Spaces ────────────────────────────────────────────────────────────

  @doc "Returns all spaces, ordered by name."
  def list_spaces do
    Space
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Returns only active spaces, ordered by name. Useful for select dropdowns."
  def list_active_spaces do
    Space
    |> where(active: true)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Gets a single space. Raises if not found."
  def get_space!(id), do: Repo.get!(Space, id)

  @doc "Returns a changeset for the given space and attrs."
  def change_space(%Space{} = space, attrs \\ %{}) do
    Space.changeset(space, attrs)
  end

  @doc "Creates a space."
  def create_space(attrs \\ %{}) do
    %Space{}
    |> Space.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a space."
  def update_space(%Space{} = space, attrs) do
    space
    |> Space.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a space."
  def delete_space(%Space{} = space) do
    Repo.delete(space)
  end

  # ── Space Rentals ─────────────────────────────────────────────────────

  @doc """
  Returns a list of space rentals.

  Options:
    - `:status` — filter by status string
    - `:space_id` — filter by space
    - `:from` — filter rentals starting after this datetime
    - `:to` — filter rentals starting before this datetime
  """
  def list_space_rentals(opts \\ []) do
    status = Keyword.get(opts, :status)
    space_id = Keyword.get(opts, :space_id)
    from_dt = Keyword.get(opts, :from)
    to_dt = Keyword.get(opts, :to)

    SpaceRental
    |> maybe_filter_status(status)
    |> maybe_filter_space(space_id)
    |> maybe_filter_from(from_dt)
    |> maybe_filter_to(to_dt)
    |> order_by(desc: :inserted_at)
    |> preload([:space, :customer])
    |> Repo.all()
  end

  @doc "Gets a single space rental with space and customer preloaded. Raises if not found."
  def get_space_rental!(id) do
    SpaceRental
    |> preload([:space, :customer])
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for the given rental and attrs."
  def change_space_rental(%SpaceRental{} = rental, attrs \\ %{}) do
    SpaceRental.changeset(rental, attrs)
  end

  @doc "Creates a space rental."
  def create_space_rental(attrs \\ %{}) do
    %SpaceRental{}
    |> SpaceRental.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a space rental."
  def update_space_rental(%SpaceRental{} = rental, attrs) do
    rental
    |> SpaceRental.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records payment for a space rental.

  In a transaction:
    1. Sets paid_at to today's date
    2. Creates journal entry: DR Cash / CR Rental Revenue + optionally CR IVA Payable
  """
  def record_payment(%SpaceRental{paid_at: nil} = rental) do
    Repo.transaction(fn ->
      updated =
        rental
        |> SpaceRental.changeset(%{paid_at: Date.utc_today()})
        |> Repo.update!()

      VolumeStudioAccounting.record_space_rental_payment(updated)

      updated
    end)
  end

  def record_payment(%SpaceRental{} = _rental) do
    {:error, :already_paid}
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_space(query, nil), do: query
  defp maybe_filter_space(query, id), do: where(query, space_id: ^id)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, dt), do: where(query, [r], r.starts_at >= ^dt)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, dt), do: where(query, [r], r.starts_at <= ^dt)
end
