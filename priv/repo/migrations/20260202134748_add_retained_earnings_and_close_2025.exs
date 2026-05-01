defmodule Ledgr.Repo.Migrations.AddRetainedEarningsAndClose2025 do
  use Ecto.Migration
  import Ecto.Query

  @close_date ~D[2025-12-31]

  def up do
    # Step 1: Insert Retained Earnings account if it doesn't exist
    retained_earnings_account =
      insert_account_if_not_exists("3050", "Retained Earnings", "equity", "credit")

    # Step 2: Ensure Owner's Drawings account exists
    owners_drawings_account =
      insert_account_if_not_exists("3100", "Owner's Drawings", "equity", "debit")

    # Step 3: Calculate amounts and create closing entry
    if retained_earnings_account do
      create_closing_entry(retained_earnings_account.id, owners_drawings_account)
    end
  end

  def down do
    # Remove the closing entry
    execute """
    DELETE FROM journal_lines
    WHERE journal_entry_id IN (
      SELECT id FROM journal_entries WHERE entry_type = 'year_end_close'
    )
    """

    execute """
    DELETE FROM journal_entries WHERE entry_type = 'year_end_close'
    """
  end

  defp insert_account_if_not_exists(code, name, type, normal_balance) do
    existing =
      Ledgr.Repo.one(
        from(a in "accounts",
          where: a.code == ^code,
          select: %{id: a.id}
        )
      )

    if existing do
      existing
    else
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {1, [account]} =
        Ledgr.Repo.insert_all(
          "accounts",
          [
            %{
              code: code,
              name: name,
              type: type,
              normal_balance: normal_balance,
              is_cash: false,
              inserted_at: now,
              updated_at: now
            }
          ],
          returning: [:id]
        )

      account
    end
  end

  defp create_closing_entry(retained_earnings_account_id, owners_drawings_account) do
    # Check if closing entry already exists
    existing_close =
      Ledgr.Repo.one(
        from(je in "journal_entries",
          where: je.entry_type == "year_end_close" and je.reference == "Year-End Close 2025",
          select: je.id
        )
      )

    if existing_close do
      # Already closed, skip
      :ok
    else
      # Calculate net income through close date
      net_income_cents = calculate_net_income(@close_date)

      # Calculate Owner's Drawings balance through close date
      owners_drawings_cents =
        if owners_drawings_account do
          calculate_owners_drawings(@close_date, owners_drawings_account.id)
        else
          0
        end

      # Amount to credit Retained Earnings = Net Income - Owner's Drawings
      # (Owner's Drawings reduces the amount transferred to Retained Earnings)
      amount_to_close = net_income_cents - owners_drawings_cents

      if amount_to_close != 0 or owners_drawings_cents != 0 do
        create_closing_journal_entry(
          retained_earnings_account_id,
          owners_drawings_account,
          net_income_cents,
          owners_drawings_cents,
          amount_to_close
        )
      end
    end
  end

  defp calculate_net_income(end_date) do
    # Sum all revenue (credits - debits for credit-normal accounts)
    revenue_query =
      from(je in "journal_entries",
        join: jl in "journal_lines",
        on: jl.journal_entry_id == je.id,
        join: a in "accounts",
        on: jl.account_id == a.id,
        where: a.type == "revenue" and je.date <= ^end_date,
        select: coalesce(sum(jl.credit_cents), 0) - coalesce(sum(jl.debit_cents), 0)
      )

    revenue_cents = Ledgr.Repo.one(revenue_query) || 0

    # Sum all expenses (debits - credits for debit-normal accounts)
    expense_query =
      from(je in "journal_entries",
        join: jl in "journal_lines",
        on: jl.journal_entry_id == je.id,
        join: a in "accounts",
        on: jl.account_id == a.id,
        where: a.type == "expense" and je.date <= ^end_date,
        select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
      )

    expense_cents = Ledgr.Repo.one(expense_query) || 0

    # Net income = Revenue - Expenses
    revenue_cents - expense_cents
  end

  defp calculate_owners_drawings(end_date, owners_drawings_account_id) do
    # Owner's Drawings has a debit normal balance
    # Sum debits - credits to get the balance
    query =
      from(je in "journal_entries",
        join: jl in "journal_lines",
        on: jl.journal_entry_id == je.id,
        where: jl.account_id == ^owners_drawings_account_id and je.date <= ^end_date,
        select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
      )

    Ledgr.Repo.one(query) || 0
  end

  defp create_closing_journal_entry(
         retained_earnings_account_id,
         owners_drawings_account,
         _net_income_cents,
         owners_drawings_cents,
         amount_to_close
       ) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Create the journal entry
    {1, [journal_entry]} =
      Ledgr.Repo.insert_all(
        "journal_entries",
        [
          %{
            date: @close_date,
            entry_type: "year_end_close",
            reference: "Year-End Close 2025",
            description: "Close 2025 net income and owner's drawings to retained earnings",
            inserted_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    lines = []

    # Line 1: Close Owner's Drawings (credit to zero it out)
    lines =
      if owners_drawings_cents > 0 and owners_drawings_account do
        lines ++
          [
            %{
              journal_entry_id: journal_entry.id,
              account_id: owners_drawings_account.id,
              debit_cents: 0,
              credit_cents: owners_drawings_cents,
              description: "Close owner's drawings",
              inserted_at: now,
              updated_at: now
            }
          ]
      else
        lines
      end

    # Line 2: Credit/Debit Retained Earnings for the net amount
    lines =
      if amount_to_close >= 0 do
        lines ++
          [
            %{
              journal_entry_id: journal_entry.id,
              account_id: retained_earnings_account_id,
              debit_cents: 0,
              credit_cents: amount_to_close,
              description: "Net income closed to retained earnings",
              inserted_at: now,
              updated_at: now
            }
          ]
      else
        lines ++
          [
            %{
              journal_entry_id: journal_entry.id,
              account_id: retained_earnings_account_id,
              debit_cents: abs(amount_to_close),
              credit_cents: 0,
              description: "Net loss closed to retained earnings",
              inserted_at: now,
              updated_at: now
            }
          ]
      end

    if length(lines) > 0 do
      Ledgr.Repo.insert_all("journal_lines", lines)
    end

    :ok
  end
end
