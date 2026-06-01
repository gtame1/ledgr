defmodule Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  schema "consultation_payout_decisions" do
    field :consultation_id, :string
    field :pay_doctor, :boolean, default: true
    field :reason, :string
    field :decided_by, :string

    timestamps()
  end

  @required ~w[consultation_id pay_doctor]a
  @optional ~w[reason decided_by]a

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:consultation_id)
  end
end
