defmodule Ledgr.Core.Reconciliation do
  @moduledoc """
  Reconciliation context for inventory and accounting reconciliation.
  """
  require Logger
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{Account, JournalLine}

  # ---------- Account Reconciliation ----------

  @doc """
  Get the current balance of an account as of a given date.
  Returns balance in cents (positive for debit balance accounts, negative for credit balance accounts).
  """
  def get_account_balance(account_id, as_of_date \\ LedgrWeb.Helpers.DomainHelpers.today_mx()) do
    account = Repo.get!(Account, account_id)

    query =
      from jl in JournalLine,
        join: je in assoc(jl, :journal_entry),
        where: jl.account_id == ^account_id,
        where: je.date <= ^as_of_date

    result =
      query
      |> group_by([jl], jl.account_id)
      |> select([jl], %{
        total_debits: fragment("COALESCE(SUM(?), 0)", jl.debit_cents),
        total_credits: fragment("COALESCE(SUM(?), 0)", jl.credit_cents)
      })
      |> Repo.one()

    total_debits = if result, do: result.total_debits, else: 0
    total_credits = if result, do: result.total_credits, else: 0

    case account.normal_balance do
      "debit" -> total_debits - total_credits
      "credit" -> total_credits - total_debits
      _ -> total_debits - total_credits
    end
  end

  @doc """
  Get all accounts with their current balances for reconciliation.
  Returns a list of maps with account info and balance.
  """
  def list_accounts_for_reconciliation(as_of_date \\ LedgrWeb.Helpers.DomainHelpers.today_mx()) do
    from(a in Account,
      where: a.type in ["asset", "liability"],
      order_by: a.code
    )
    |> Repo.all()
    |> Enum.map(fn account ->
      balance_cents = get_account_balance(account.id, as_of_date)
      %{
        account: account,
        balance_cents: balance_cents,
        balance_pesos: balance_cents / 100.0
      }
    end)
  end

  @doc """
  Create a reconciliation adjustment journal entry.
  Adjusts the account balance to match the actual balance.
  """
  def create_account_reconciliation(account_id, actual_balance_pesos, adjustment_date, description \\ nil) do
    account = Repo.get!(Account, account_id)
    system_balance_cents = get_account_balance(account_id, adjustment_date)
    actual_balance_cents = round(actual_balance_pesos * 100)
    difference_cents = actual_balance_cents - system_balance_cents

    if difference_cents == 0 do
      {:error, "No adjustment needed - balances match"}
    else
      # Determine which account to use for the offset
      # For asset accounts, use "Other Expenses" for losses, "Other Income" for gains
      # For liability accounts, reverse the logic
      offset_account_code = case {account.type, difference_cents > 0} do
        {"asset", true} -> "6099"  # Other Expenses (loss)
        {"asset", false} -> "6099"  # Other Expenses (gain, but we'll credit it)
        {"liability", true} -> "6099"  # Other Expenses
        {"liability", false} -> "6099"  # Other Expenses
      end

      offset_account = Accounting.get_account_by_code!(offset_account_code)

      entry_description =
        if description && String.trim(description) != "" do
          description
        else
          "Reconciliation adjustment for #{account.code} - #{account.name}"
        end

      entry_attrs = %{
        date: adjustment_date,
        entry_type: "reconciliation",
        reference: "Reconciliation: #{account.code}",
        description: entry_description
      }

      lines = case account.normal_balance do
        "debit" ->
          if difference_cents > 0 do
            # System shows less than actual - need to debit the account
            [
              %{
                account_id: account_id,
                debit_cents: difference_cents,
                credit_cents: 0,
                description: "Reconciliation adjustment - increase balance"
              },
              %{
                account_id: offset_account.id,
                debit_cents: 0,
                credit_cents: difference_cents,
                description: "Reconciliation adjustment offset"
              }
            ]
          else
            # System shows more than actual - need to credit the account
            [
              %{
                account_id: account_id,
                debit_cents: 0,
                credit_cents: abs(difference_cents),
                description: "Reconciliation adjustment - decrease balance"
              },
              %{
                account_id: offset_account.id,
                debit_cents: abs(difference_cents),
                credit_cents: 0,
                description: "Reconciliation adjustment offset"
              }
            ]
          end

        "credit" ->
          if difference_cents > 0 do
            # System shows less than actual - need to credit the account
            [
              %{
                account_id: account_id,
                debit_cents: 0,
                credit_cents: difference_cents,
                description: "Reconciliation adjustment - increase balance"
              },
              %{
                account_id: offset_account.id,
                debit_cents: difference_cents,
                credit_cents: 0,
                description: "Reconciliation adjustment offset"
              }
            ]
          else
            # System shows more than actual - need to debit the account
            [
              %{
                account_id: account_id,
                debit_cents: abs(difference_cents),
                credit_cents: 0,
                description: "Reconciliation adjustment - decrease balance"
              },
              %{
                account_id: offset_account.id,
                debit_cents: 0,
                credit_cents: abs(difference_cents),
                description: "Reconciliation adjustment offset"
              }
            ]
          end
      end

      Accounting.create_journal_entry_with_lines(entry_attrs, lines)
    end
  end

end
