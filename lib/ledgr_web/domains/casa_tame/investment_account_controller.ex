defmodule LedgrWeb.Domains.CasaTame.InvestmentAccountController do
  @moduledoc """
  Shows investment ledger accounts (code 1050-1059) and records
  movements (deposits, withdrawals, dividends, etc.) as journal entries.
  """
  use LedgrWeb, :controller
  require Logger

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Core.Reconciliation
  alias LedgrWeb.Helpers.MoneyHelper

  @investment_code_prefix "105"

  def index(conn, _params) do
    accounts =
      from(a in Account, where: like(a.code, ^"#{@investment_code_prefix}%"), order_by: a.code)
      |> Repo.all()

    accounts_with_balances =
      Enum.map(accounts, fn a ->
        balance_cents = Reconciliation.get_account_balance(a.id)
        %{account: a, balance_cents: balance_cents}
      end)

    render(conn, :index, accounts: accounts_with_balances)
  end

  def show(conn, %{"id" => id}) do
    account = Accounting.get_account!(String.to_integer(id))

    journal_lines = Accounting.list_journal_lines_by_account(account.id)

    # Compute running balance (oldest first, then reverse)
    {transactions, running_balance} = compute_running_balances(journal_lines, account)

    balance_cents = Reconciliation.get_account_balance(account.id)

    # Source accounts for movements (cash/bank accounts to move money from/to)
    source_options = source_account_options()

    render(conn, :show,
      account: account,
      transactions: transactions,
      running_balance: running_balance,
      balance_cents: balance_cents,
      source_options: source_options,
      movement_types: movement_type_options()
    )
  end

  def create_movement(conn, %{"id" => id, "movement" => params}) do
    account = Accounting.get_account!(String.to_integer(id))
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:amount_cents])

    amount = params["amount_cents"] || 0
    movement_type = params["movement_type"]
    source_account_id = params["source_account_id"]
    date = parse_date(params["date"]) || Ledgr.Domains.CasaTame.today()

    description =
      case params["description"] do
        nil -> "#{movement_type} - #{account.name}"
        "" -> "#{movement_type} - #{account.name}"
        desc -> desc
      end

    # Parse source_account_id only when needed (deposit/withdrawal)
    source_id = case source_account_id do
      nil -> nil
      "" -> nil
      id_str -> String.to_integer(id_str)
    end

    # Build journal entry lines based on movement type
    lines = case movement_type do
      "deposit" when source_id != nil ->
        # Money goes INTO investment: DR investment, CR source
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Deposit to #{account.name}"},
          %{account_id: source_id, debit_cents: 0, credit_cents: amount, description: "Transfer to #{account.name}"}
        ]

      "withdrawal" when source_id != nil ->
        # Money comes OUT of investment: DR source, CR investment
        [
          %{account_id: source_id, debit_cents: amount, credit_cents: 0, description: "Withdrawal from #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Withdrawal from #{account.name}"}
        ]

      "dividend" ->
        # Dividend income: DR investment (value increases), CR revenue
        revenue = Accounting.get_account_by_code!("4030")
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Dividend - #{account.name}"},
          %{account_id: revenue.id, debit_cents: 0, credit_cents: amount, description: "Investment return - #{account.name}"}
        ]

      "interest" ->
        # Interest earned: same as dividend
        revenue = Accounting.get_account_by_code!("4030")
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Interest earned - #{account.name}"},
          %{account_id: revenue.id, debit_cents: 0, credit_cents: amount, description: "Investment return - #{account.name}"}
        ]

      "gain_adjustment" ->
        # Unrealized gain: DR investment, CR equity (retained earnings)
        equity = Accounting.get_account_by_code!("3050")
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Market gain adjustment - #{account.name}"},
          %{account_id: equity.id, debit_cents: 0, credit_cents: amount, description: "Unrealized gain - #{account.name}"}
        ]

      "loss_adjustment" ->
        # Unrealized loss: DR equity, CR investment
        equity = Accounting.get_account_by_code!("3050")
        [
          %{account_id: equity.id, debit_cents: amount, credit_cents: 0, description: "Unrealized loss - #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Market loss adjustment - #{account.name}"}
        ]

      "fee" ->
        # Fee charged: DR expense, CR investment
        expense = Accounting.get_account_by_code!("6098")
        [
          %{account_id: expense.id, debit_cents: amount, credit_cents: 0, description: "Investment fee - #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Fee deducted - #{account.name}"}
        ]

      _ ->
        []
    end

    if lines != [] do
      case Accounting.create_journal_entry_with_lines(
        %{date: date, entry_type: "investment_deposit", description: description},
        lines
      ) do
        {:ok, _je} ->
          conn |> put_flash(:info, "Movement recorded.") |> redirect(to: dp(conn, "/investment-accounts/#{account.id}"))

        {:error, reason} ->
          Logger.warning("[CasaTame] Investment movement failed: #{inspect(reason)}")
          conn |> put_flash(:error, "Failed to record movement.") |> redirect(to: dp(conn, "/investment-accounts/#{account.id}"))
      end
    else
      Logger.warning("[CasaTame] Invalid movement type '#{movement_type}' or missing source for deposit/withdrawal")
      conn |> put_flash(:error, "Invalid movement type or missing source account.") |> redirect(to: dp(conn, "/investment-accounts/#{account.id}"))
    end
  end

  defp source_account_options do
    Repo.all(
      from a in Account,
        where: like(a.code, "10%") or like(a.code, "11%"),
        order_by: [asc: a.code]
    )
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  defp movement_type_options do
    [
      {"Deposit", "deposit"},
      {"Withdrawal", "withdrawal"},
      {"Dividend", "dividend"},
      {"Interest Earned", "interest"},
      {"Market Gain Adjustment", "gain_adjustment"},
      {"Market Loss Adjustment", "loss_adjustment"},
      {"Fee", "fee"}
    ]
  end

  defp compute_running_balances(journal_lines, account) do
    oldest_first = Enum.reverse(journal_lines)

    {running_balance, newest_first} =
      Enum.reduce(oldest_first, {0, []}, fn line, {current_balance, acc} ->
        new_balance =
          if account.normal_balance == "debit" do
            current_balance + line.debit_cents - line.credit_cents
          else
            current_balance + line.credit_cents - line.debit_cents
          end

        {new_balance, [%{line: line, balance: new_balance} | acc]}
      end)

    {newest_first, running_balance}
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str), do: Date.from_iso8601!(str)
end

defmodule LedgrWeb.Domains.CasaTame.InvestmentAccountHTML do
  use LedgrWeb, :html

  embed_templates "investment_account_html/*"
end
