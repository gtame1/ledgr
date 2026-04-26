defmodule Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplitLine

  schema "partner_splits" do
    field :name, :string
    field :notes, :string
    field :deleted_at, :utc_datetime

    has_many :lines, PartnerSplitLine, foreign_key: :partner_split_id, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @total_bps 10_000

  def changeset(split, attrs) do
    split
    |> cast(attrs, [:name, :notes])
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> cast_assoc(:lines, with: &PartnerSplitLine.changeset/2, required: true)
    |> validate_lines_sum_to_total()
    |> unique_constraint(:name)
  end

  defp validate_lines_sum_to_total(changeset) do
    case get_change(changeset, :lines) do
      nil ->
        changeset

      [] ->
        add_error(changeset, :lines, "must include at least one partner")

      line_changesets ->
        total =
          line_changesets
          |> Enum.reject(&(&1.action == :delete))
          |> Enum.map(&(get_field(&1, :share_bps) || 0))
          |> Enum.sum()

        if total == @total_bps do
          changeset
        else
          add_error(
            changeset,
            :lines,
            "must sum to 100% (got #{Float.round(total / 100, 2)}%)"
          )
        end
    end
  end

  def total_bps, do: @total_bps
end
