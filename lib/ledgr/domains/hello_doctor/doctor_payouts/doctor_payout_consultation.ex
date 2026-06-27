defmodule Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayoutConsultation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayout

  schema "doctor_payout_consultations" do
    # How much of the parent payout was paid toward this consultation.
    # See DoctorPayouts for the allocation rule.
    field :amount_cents, :integer
    belongs_to :doctor_payout, DoctorPayout
    belongs_to :consultation, Consultation, type: :string

    timestamps()
  end

  @required ~w[doctor_payout_id consultation_id]a
  @optional ~w[amount_cents]a

  def changeset(record, attrs) do
    record
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:doctor_payout_id, :consultation_id],
      name: :doctor_payout_consultations_payout_consultation_index
    )
    |> foreign_key_constraint(:doctor_payout_id)
    |> foreign_key_constraint(:consultation_id)
  end
end
