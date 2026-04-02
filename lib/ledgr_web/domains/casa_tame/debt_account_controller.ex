defmodule LedgrWeb.Domains.CasaTame.DebtAccountController do
  @moduledoc """
  Shows debt/liability ledger accounts (codes 2xxx) and records
  movements (payments, charges, interest, etc.) as journal entries.
  """
  use LedgrWeb, :controller
  require Logger

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.Account
  alias Ledgr.Core.Reconciliation
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    accounts =
      from(a in Account, where: a.type == "liability", order_by: a.code)
      |> Repo.all()

    accounts_with_balances =
      Enum.map(accounts, fn a ->
        balance_cents = Reconciliation.get_account_balance(a.id)
        %{account: a, balance_cents: balance_cents}
      end)

    # Group by type based on code ranges
    grouped = %{
      credit_cards_usd: Enum.filter(accounts_with_balances, & &1.account.code >= "2000" and &1.account.code < "2010"),
      ap_usd: Enum.filter(accounts_with_balances, & &1.account.code >= "2010" and &1.account.code < "2050"),
      loans_usd: Enum.filter(accounts_with_balances, & &1.account.code >= "2050" and &1.account.code < "2100"),
      credit_cards_mxn: Enum.filter(accounts_with_balances, & &1.account.code >= "2100" and &1.account.code < "2110"),
      ap_mxn: Enum.filter(accounts_with_balances, & &1.account.code >= "2110" and &1.account.code < "2150"),
      loans_mxn: Enum.filter(accounts_with_balances, & &1.account.code >= "2150" and &1.account.code < "2200")
    }

    total = Enum.reduce(accounts_with_balances, 0, & &1.balance_cents + &2)

    render(conn, :index, grouped: grouped, total_cents: total)
  end

  def show(conn, %{"id" => id}) do
    account = Accounting.get_account!(String.to_integer(id))
    journal_lines = Accounting.list_journal_lines_by_account(account.id)
    {transactions, running_balance} = compute_running_balances(journal_lines, account)
    balance_cents = Reconciliation.get_account_balance(account.id)

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

    lines = case movement_type do
      "payment" ->
        # Pay down debt: DR liability (reduces balance), CR cash source
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Payment - #{account.name}"},
          %{account_id: String.to_integer(source_account_id), debit_cents: 0, credit_cents: amount, description: "Payment to #{account.name}"}
        ]

      "charge" ->
        # New charge on credit: DR expense, CR liability (increases balance)
        # For charges, source_account is the expense account
        [
          %{account_id: String.to_integer(source_account_id), debit_cents: amount, credit_cents: 0, description: "Charge on #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Charge - #{account.name}"}
        ]

      "interest" ->
        # Interest accrual: DR interest expense, CR liability
        expense = Accounting.get_account_by_code!("6098")
        [
          %{account_id: expense.id, debit_cents: amount, credit_cents: 0, description: "Interest - #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Interest accrual - #{account.name}"}
        ]

      "fee" ->
        # Fee: DR financial expense, CR liability
        expense = Accounting.get_account_by_code!("6098")
        [
          %{account_id: expense.id, debit_cents: amount, credit_cents: 0, description: "Fee - #{account.name}"},
          %{account_id: account.id, debit_cents: 0, credit_cents: amount, description: "Fee - #{account.name}"}
        ]

      "refund" ->
        # Refund: DR liability, CR revenue/other income
        income = Accounting.get_account_by_code!("4050")
        [
          %{account_id: account.id, debit_cents: amount, credit_cents: 0, description: "Refund - #{account.name}"},
          %{account_id: income.id, debit_cents: 0, credit_cents: amount, description: "Refund from #{account.name}"}
        ]

      _ ->
        []
    end

    if lines != [] do
      case Accounting.create_journal_entry_with_lines(
        %{date: date, entry_type: "debt_payment", description: description},
        lines
      ) do
        {:ok, _je} ->
          conn |> put_flash(:info, "Movement recorded.") |> redirect(to: dp(conn, "/debt-accounts/#{account.id}"))

        {:error, reason} ->
          Logger.warning("[CasaTame] Debt movement failed: #{inspect(reason)}")
          conn |> put_flash(:error, "Failed to record movement.") |> redirect(to: dp(conn, "/debt-accounts/#{account.id}"))
      end
    else
      Logger.warning("[CasaTame] Invalid debt movement type '#{movement_type}'")
      conn |> put_flash(:error, "Invalid movement type.") |> redirect(to: dp(conn, "/debt-accounts/#{account.id}"))
    end
  end

  defp source_account_options do
    # For payments: cash/bank accounts. For charges: expense accounts. Combined list.
    cash_accounts =
      Repo.all(from a in Account, where: like(a.code, "10%") or like(a.code, "11%"), order_by: a.code)
      |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})

    expense_accounts =
      Repo.all(from a in Account, where: a.type == "expense", order_by: a.code)
      |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})

    [{"— Cash & Bank —", ""}] ++ cash_accounts ++ [{"— Expense Accounts —", ""}] ++ expense_accounts
  end

  defp movement_type_options do
    [
      {"Payment", "payment"},
      {"Charge (new purchase)", "charge"},
      {"Interest Accrual", "interest"},
      {"Fee", "fee"},
      {"Refund / Credit", "refund"}
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

defmodule LedgrWeb.Domains.CasaTame.DebtAccountHTML do
  use LedgrWeb, :html

  embed_templates "debt_account_html/*"
end
