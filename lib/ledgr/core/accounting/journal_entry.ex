defmodule Ledgr.Core.Accounting.JournalEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Core.Accounting.JournalLine

  schema "journal_entries" do
    field :date, :date
    field :description, :string
    field :reference, :string
    field :entry_type, :string
    field :payee, :string

    has_many :journal_lines, JournalLine, on_replace: :delete

    timestamps()
  end

  @core_types ~w(
    sale
    expense
    investment
    withdrawal
    inventory_purchase
    internal_transfer
    reconciliation
    year_end_close
    depreciation
    other
  )

  @core_entry_types [
    {"Sale", "sale"},
    {"Expense", "expense"},
    {"Investment (Owner In)", "investment"},
    {"Withdrawal (Owner Out)", "withdrawal"},
    {"Inventory Purchase", "inventory_purchase"},
    {"Internal Transfer", "internal_transfer"},
    {"Reconciliation", "reconciliation"},
    {"Year-End Close", "year_end_close"},
    {"Depreciation", "depreciation"},
    {"Other", "other"}
  ]

  def types do
    domain = Ledgr.Domain.current()

    domain_types =
      if domain, do: domain.journal_entry_types() |> Enum.map(&elem(&1, 1)), else: []

    @core_types ++ domain_types
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:date, :description, :reference, :entry_type, :payee])
    |> validate_required([:date, :description, :entry_type])
    |> validate_inclusion(:entry_type, types())
    |> cast_assoc(:journal_lines, with: &JournalLine.changeset/2)
    |> validate_lines_valid()
    |> validate_balanced()
  end

  # ----- ACCESOR FUNCTIONS -----
  def entry_types do
    domain = Ledgr.Domain.current()

    domain_entry_types =
      if domain, do: domain.journal_entry_types(), else: []

    @core_entry_types ++ domain_entry_types
  end

  # ----- VALIDATION FUNCTIONS -----
  defp validate_lines_valid(changeset) do
    line_changesets =
      changeset
      |> get_change(:journal_lines, [])

    # if any nested line is invalid, add a parent error on :journal_lines
    if Enum.any?(line_changesets, &match?(%Ecto.Changeset{valid?: false}, &1)) do
      add_error(changeset, :journal_lines, "Some lines are incomplete or invalid")
    else
      changeset
    end
  end

  # ------- BALANCE CHECK -------

  defp validate_balanced(changeset) do
    # If nothing was sent for journal_lines, this will be [] instead of nil
    line_changesets = get_change(changeset, :journal_lines, [])

    {debits, credits} =
      Enum.reduce(line_changesets, {0, 0}, fn line_cs, {d_acc, c_acc} ->
        {d, c} = extract_amounts(line_cs)
        {d_acc + d, c_acc + c}
      end)

    # If user submitted nothing at all for lines, let other validations complain,
    # and don't run the equality rule.
    cond do
      debits == 0 and credits == 0 ->
        changeset

      debits != credits ->
        add_error(changeset, :base, "Debits and credits must be equal and non-zero")

      true ->
        changeset
    end
  end

  # Handle both nested changesets and plain maps, safely
  defp extract_amounts(%Ecto.Changeset{} = cs) do
    debit = get_field(cs, :debit_cents) || 0
    credit = get_field(cs, :credit_cents) || 0
    {debit, credit}
  end

  defp extract_amounts(%{} = attrs) do
    debit =
      Map.get(attrs, "debit_cents") ||
        Map.get(attrs, :debit_cents) ||
        0

    credit =
      Map.get(attrs, "credit_cents") ||
        Map.get(attrs, :credit_cents) ||
        0

    {debit || 0, credit || 0}
  end
end
