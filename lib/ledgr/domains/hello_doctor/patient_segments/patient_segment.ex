defmodule Ledgr.Domains.HelloDoctor.PatientSegments.PatientSegment do
  @moduledoc """
  Ledgr-owned snapshot of a patient's lifecycle tier (L0–L3). Materialized
  by `Ledgr.Domains.HelloDoctor.PatientSegments.recompute/0`. See that
  module for the tier definitions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "patient_segments" do
    field :patient_id, :string
    field :tier, :string
    field :inbound_messages, :integer, default: 0
    field :consult_count, :integer, default: 0
    field :computed_at, :utc_datetime

    timestamps()
  end

  @fields ~w[patient_id tier inbound_messages consult_count computed_at]a

  def changeset(segment, attrs) do
    segment
    |> cast(attrs, @fields)
    |> validate_required([:patient_id, :tier])
    |> validate_inclusion(:tier, ~w[L0 L1 L2 L3])
    |> unique_constraint(:patient_id)
  end
end
