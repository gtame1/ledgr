defmodule Ledgr.Domains.HelloDoctor.Specialties.Specialty do
  use Ecto.Schema
  import Ecto.Changeset

  schema "specialties" do
    field :name, :string
    field :is_active, :boolean, default: true
    field :prescrypto_specialty_id, :integer

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(specialty, attrs) do
    specialty
    |> cast(attrs, [:name, :is_active, :prescrypto_specialty_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
    |> unique_constraint(:name, message: "already exists")
  end
end
