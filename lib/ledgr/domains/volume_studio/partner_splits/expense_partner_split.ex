defmodule Ledgr.Domains.VolumeStudio.PartnerSplits.ExpensePartnerSplit do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit

  @primary_key false
  schema "expense_partner_splits" do
    belongs_to :expense, Expense, primary_key: true
    belongs_to :partner_split, PartnerSplit

    timestamps(type: :utc_datetime)
  end

  def changeset(eps, attrs) do
    eps
    |> cast(attrs, [:expense_id, :partner_split_id])
    |> validate_required([:expense_id, :partner_split_id])
    |> foreign_key_constraint(:partner_split_id)
  end
end
