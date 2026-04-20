defmodule Ledgr.Domains.HelloDoctor.Doctors.Doctor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "doctors" do
    field :phone, :string
    field :name, :string
    field :specialty, :string
    field :cedula_profesional, :string
    field :university, :string
    field :years_experience, :integer
    field :email, :string
    field :is_available, :boolean, default: true
    field :accepts_video_calls, :boolean, default: true
    field :terms_accepted, :boolean, default: false
    field :terms_accepted_at, :utc_datetime
    field :extension_code, :string

    has_many :consultations, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    has_many :prescriptions, Ledgr.Domains.HelloDoctor.Prescriptions.Prescription

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  @required ~w[id phone name specialty is_available]a
  @optional ~w[cedula_profesional university years_experience email accepts_video_calls terms_accepted terms_accepted_at extension_code]a

  def changeset(doctor, attrs) do
    doctor
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
