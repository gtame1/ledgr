defmodule Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplitLine do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Partners.Partner
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit

  schema "partner_split_lines" do
    belongs_to :partner_split, PartnerSplit
    belongs_to :partner, Partner

    field :share_bps, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:partner_id, :share_bps])
    |> validate_required([:partner_id, :share_bps])
    |> validate_number(:share_bps, greater_than: 0, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:partner_id)
    |> unique_constraint([:partner_split_id, :partner_id],
      message: "partner already in this split"
    )
  end
end
