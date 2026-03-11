defmodule Ledgr.Domains.VolumeStudio.Instructors.Instructor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "instructors" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :specialty, :string
    field :bio, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name]
  @optional_fields [:email, :phone, :specialty, :bio, :active]

  def changeset(instructor, attrs) do
    instructor
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
  end
end
