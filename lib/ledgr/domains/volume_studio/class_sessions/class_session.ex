defmodule Ledgr.Domains.VolumeStudio.ClassSessions.ClassSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor
  alias Ledgr.Domains.VolumeStudio.ClassSessions.ClassBooking

  schema "class_sessions" do
    belongs_to :instructor, Instructor
    has_many :class_bookings, ClassBooking

    field :name, :string
    field :scheduled_at, :utc_datetime
    field :duration_minutes, :integer, default: 60
    field :capacity, :integer
    field :status, :string, default: "scheduled"
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :scheduled_at, :instructor_id]
  @optional_fields [:duration_minutes, :capacity, :status, :notes]

  @valid_statuses ~w(scheduled completed cancelled)

  def changeset(session, attrs) do
    session
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:capacity, greater_than: 0)
    |> foreign_key_constraint(:instructor_id)
  end
end
