defmodule Ledgr.Domains.AumentaMiPension.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "agents" do
    field :phone, :string
    field :name, :string
    field :email, :string
    field :is_available, :boolean, default: true
    field :accepts_video_calls, :boolean, default: true
    field :terms_accepted, :boolean, default: false
    field :terms_accepted_at, :naive_datetime

    has_many :consultations, Ledgr.Domains.AumentaMiPension.Consultations.Consultation

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  @required ~w[id phone name is_available]a
  @optional ~w[email accepts_video_calls terms_accepted terms_accepted_at]a

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @required ++ @optional)
    |> normalize_phone()
    |> validate_required(@required)
    |> unique_constraint(:phone)
  end

  defp normalize_phone(changeset) do
    case get_change(changeset, :phone) do
      nil -> changeset
      phone -> put_change(changeset, :phone, String.replace(phone, ~r/[^0-9]/, ""))
    end
  end
end
