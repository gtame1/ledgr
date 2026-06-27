defmodule Ledgr.Domains.HelloDoctor.ConsultationPayouts.ConsultationPayout do
  @moduledoc """
  Frozen-at-delivery snapshot of the doctor share earned for one
  consultation. See `Ledgr.Domains.HelloDoctor.ConsultationPayouts`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "consultation_payouts" do
    field :consultation_id, :string
    field :doctor_id, :string
    field :doctor_share_cents, :integer
    field :payment_source, :string
    field :computed_at, :utc_datetime

    timestamps()
  end

  @required ~w[consultation_id doctor_share_cents]a
  @optional ~w[doctor_id payment_source computed_at]a

  def changeset(payout, attrs) do
    payout
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:doctor_share_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:consultation_id)
  end
end
