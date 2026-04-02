defmodule Ledgr.Domains.MrMunchMe.Inventory.MovementForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :movement_type, :string        # "usage" | "transfer" | "write_off"
    field :ingredient_code, :string
    field :from_location_code, :string
    field :to_location_code, :string
    field :quantity, :integer
    field :movement_date, :date
    field :note, :string
  end

  @types ~w(usage transfer write_off)

  def changeset(form, attrs) do
    form
    |> cast(attrs, [
      :movement_type,
      :ingredient_code,
      :from_location_code,
      :to_location_code,
      :quantity,
      :movement_date,
      :note
    ])
    |> validate_required([:movement_type, :ingredient_code, :quantity])
    |> validate_inclusion(:movement_type, @types)
    |> validate_number(:quantity, greater_than: 0)
    |> put_default_movement_date()
    |> validate_locations()
  end

  defp put_default_movement_date(changeset) do
    case get_field(changeset, :movement_date) do
      nil -> put_change(changeset, :movement_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
      _ -> changeset
    end
  end

  # Require different fields depending on type
  defp validate_locations(changeset) do
    case get_field(changeset, :movement_type) do
      "usage" ->
        changeset
        |> validate_required([:from_location_code])

      "transfer" ->
        changeset
        |> validate_required([:from_location_code, :to_location_code])
        |> validate_change(:to_location_code, fn :to_location_code, to_code ->
          from_code = get_field(changeset, :from_location_code)

          if from_code == to_code do
            [to_location_code: "Destination must be different from origin"]
          else
            []
          end
        end)

      "write_off" ->
        # we are "throwing out" inventory from a location, no destination
        changeset
        |> validate_required([:from_location_code])

      _ ->
        changeset
    end
  end

end
