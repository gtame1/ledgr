defmodule Ledgr.Domains.MrMunchMe.Inventory.MovementListForm do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.MrMunchMe.Inventory.MovementItemForm

  @primary_key false
  embedded_schema do
    field :movement_type, :string
    field :from_location_code, :string
    field :to_location_code, :string
    field :movement_date, :date
    field :note, :string

    embeds_many :items, MovementItemForm, on_replace: :delete
  end

  @types ~w(usage transfer write_off)

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:movement_type, :from_location_code, :to_location_code, :movement_date, :note])
    |> validate_required([:movement_type, :movement_date])
    |> validate_inclusion(:movement_type, @types)
    |> put_default_movement_date()
    |> cast_embed(:items, with: &MovementItemForm.changeset/2, required: true)
    |> validate_length(:items, min: 1, message: "must have at least one item")
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
        changeset
        |> validate_required([:from_location_code])

      _ ->
        changeset
    end
  end
end
