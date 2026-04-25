defmodule Ledgr.Domains.CasaTame.Expenses.ExpenseAttachment do
  @moduledoc """
  A receipt or document attached to an expense.
  Files are stored on disk; this record tracks metadata.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "expense_attachments" do
    field :filename, :string
    field :stored_path, :string
    field :content_type, :string
    field :file_size, :integer

    belongs_to :expense, Ledgr.Domains.CasaTame.Expenses.CasaTameExpense

    timestamps()
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:expense_id, :filename, :stored_path, :content_type, :file_size])
    |> validate_required([:expense_id, :filename, :stored_path])
  end
end
