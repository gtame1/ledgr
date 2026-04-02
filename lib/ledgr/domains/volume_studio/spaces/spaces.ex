defmodule Ledgr.Domains.VolumeStudio.Spaces do
  @moduledoc """
  Context module for managing Volume Studio spaces and space rentals.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Spaces.{Space, SpaceRental, SpaceRentalPayment}
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  # ── Spaces ────────────────────────────────────────────────────────────

  @doc "Returns all spaces, ordered by name."
  def list_spaces do
    Space
    |> where([s], is_nil(s.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Returns only active spaces, ordered by name. Useful for select dropdowns."
  def list_active_spaces do
    Space
    |> where([s], s.active == true and is_nil(s.deleted_at))
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Gets a single space. Raises if not found."
  def get_space!(id) do
    from(s in Space, where: s.id == ^id and is_nil(s.deleted_at))
    |> Repo.one!()
  end

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

  @doc "Soft-deletes a space."
  def delete_space(%Space{} = space) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    space
    |> Ecto.Changeset.change(deleted_at: now)
    |> Repo.update()
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
    |> where([r], is_nil(r.deleted_at))
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
    from(r in SpaceRental, where: r.id == ^id and is_nil(r.deleted_at))
    |> preload([:space, :customer])
    |> Repo.one!()
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
  Returns a payment summary map for a space rental.

    %{
      base_cents:        integer,   # amount_cents (pre-IVA)
      iva_cents:         integer,   # 16% of base
      discount_cents:    integer,   # flat discount on total
      total_cents:       integer,   # base + iva − discount, ≥ 0
      paid_cents:        integer,   # total cash received so far
      outstanding_cents: integer    # total − paid, ≥ 0
    }
  """
  def payment_summary(%SpaceRental{} = r) do
    base     = r.amount_cents   || 0
    iva      = r.iva_cents      || 0
    discount = r.discount_cents || 0
    total    = max(base + iva - discount, 0)
    paid     = r.paid_cents     || 0

    %{
      base_cents:        base,
      iva_cents:         iva,
      discount_cents:    discount,
      total_cents:       total,
      paid_cents:        paid,
      outstanding_cents: max(total - paid, 0)
    }
  end

  @doc """
  Records a (partial or full) payment for a space rental.

  `attrs` map:
    - `:amount_cents`    — required, amount being paid now
    - `:payment_date`    — defaults to today
    - `:method`         — optional string (cash/card/transfer/other)
    - `:note`           — optional string

  In a transaction:
    1. Increments paid_cents by amount_cents
    2. Sets paid_at when fully paid
    3. Creates journal entry via VolumeStudioAccounting
  """
  def record_payment(%SpaceRental{} = rental, attrs) do
    amount  = Map.fetch!(attrs, :amount_cents)
    summary = payment_summary(rental)
    new_paid = rental.paid_cents + amount
    paid_at  = if new_paid >= summary.total_cents, do: Map.get(attrs, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx()), else: nil

    Repo.transaction(fn ->
      updated =
        rental
        |> SpaceRental.payment_changeset(%{paid_cents: new_paid, paid_at: paid_at})
        |> Repo.update!()

      %SpaceRentalPayment{}
      |> SpaceRentalPayment.changeset(%{
        space_rental_id: rental.id,
        amount_cents:    amount,
        payment_date:    Map.get(attrs, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx()),
        method:          Map.get(attrs, :method),
        note:            Map.get(attrs, :note)
      })
      |> Repo.insert!()

      VolumeStudioAccounting.record_space_rental_payment(updated, attrs)

      updated
    end)
  end

  @doc "Returns all payments for a space rental, ordered oldest first."
  def list_rental_payments(%SpaceRental{} = rental) do
    SpaceRentalPayment
    |> where(space_rental_id: ^rental.id)
    |> order_by(asc: :payment_date, asc: :inserted_at)
    |> Repo.all()
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
