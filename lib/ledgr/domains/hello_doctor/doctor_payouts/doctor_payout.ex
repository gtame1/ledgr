defmodule Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayout do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.DoctorPayouts.DoctorPayoutConsultation

  @payment_methods ~w[bank_transfer cash spei other]

  schema "doctor_payouts" do
    field :payout_date, :date
    field :amount_cents, :integer
    field :payment_method, :string, default: "bank_transfer"
    field :reference, :string
    field :notes, :string
    field :journal_entry_id, :integer

    belongs_to :doctor, Doctor, type: :string

    has_many :payout_consultations, DoctorPayoutConsultation,
      foreign_key: :doctor_payout_id,
      on_replace: :delete

    timestamps()
  end

  @required ~w[doctor_id payout_date amount_cents payment_method]a
  @optional ~w[reference notes journal_entry_id]a

  def changeset(payout, attrs) do
    payout
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:payment_method, @payment_methods)
    # $0 is allowed — represents a payout that was "processed" without any
    # actual cash movement (e.g. refunded consultation the doctor isn't owed
    # for, or settled-offline cases). No journal entry is created in that case.
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:doctor_id)
  end

  def payment_methods, do: @payment_methods
end
