defmodule Ledgr.Core.AccountingFixtures do
  @moduledoc """
  Test helpers for creating accounting entities.
  """

  alias Ledgr.Core.Accounting

  @doc """
  Create all the standard accounts needed for order processing.
  Returns a map of accounts by their code.
  """
  def standard_accounts_fixture do
    accounts = [
      %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
      %{
        code: "1100",
        name: "Accounts Receivable",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "1200",
        name: "Ingredients Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "1210",
        name: "Packing Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "1220",
        name: "WIP Inventory",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "2200",
        name: "Customer Deposits",
        type: "liability",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "3000",
        name: "Owner's Equity",
        type: "equity",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "3050",
        name: "Retained Earnings",
        type: "equity",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "3100",
        name: "Owner's Drawings",
        type: "equity",
        normal_balance: "debit",
        is_cash: false
      },
      %{
        code: "4000",
        name: "Sales Revenue",
        type: "revenue",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "4020",
        name: "Shipping Revenue",
        type: "revenue",
        normal_balance: "credit",
        is_cash: false
      },
      %{
        code: "5000",
        name: "Ingredients COGS",
        type: "expense",
        normal_balance: "debit",
        is_cash: false,
        is_cogs: true
      },
      %{
        code: "5010",
        name: "Packing COGS",
        type: "expense",
        normal_balance: "debit",
        is_cash: false,
        is_cogs: true
      }
    ]

    created_accounts =
      Enum.map(accounts, fn attrs ->
        # Try to get existing account first, or create if doesn't exist
        case Accounting.get_account_by_code(attrs.code) do
          nil ->
            {:ok, account} = Accounting.create_account(attrs)
            {account.code, account}

          existing ->
            {existing.code, existing}
        end
      end)
      |> Map.new()

    created_accounts
  end

  @doc """
  Create a single account with the given attributes.
  """
  def account_fixture(attrs \\ %{}) do
    {:ok, account} =
      attrs
      |> Enum.into(%{
        code: "ACC_#{System.unique_integer([:positive])}",
        name: "Test Account",
        type: "asset",
        normal_balance: "debit",
        is_cash: false
      })
      |> Accounting.create_account()

    account
  end

  @doc """
  Create a cash account.
  """
  def cash_account_fixture(attrs \\ %{}) do
    account_fixture(
      Map.merge(
        %{
          code: "CASH_#{System.unique_integer([:positive])}",
          name: "Test Cash Account",
          type: "asset",
          normal_balance: "debit",
          is_cash: true
        },
        attrs
      )
    )
  end
end
