defmodule LedgrWeb.Domains.CasaTame.ExpenseController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Expenses
  alias Ledgr.Domains.CasaTame.Expenses.CasaTameExpense, as: Expense
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    expenses =
      Expenses.list_expenses(
        currency: params["currency"],
        date_from: params["date_from"],
        date_to: params["date_to"]
      )

    render(conn, :index,
      expenses: expenses,
      currency_filter: params["currency"] || "",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || ""
    )
  end

  def new(conn, params) do
    # Support prefilled values from bill payment flow
    date =
      case params["date"] do
        nil ->
          Ledgr.Domains.CasaTame.today()

        d ->
          case Date.from_iso8601(d) do
            {:ok, date} -> date
            _ -> Ledgr.Domains.CasaTame.today()
          end
      end

    prefill = %Expense{
      date: date,
      currency: params["currency"] || "MXN",
      description: params["description"],
      expense_account_id:
        if(params["expense_account_id"] && params["expense_account_id"] != "",
          do: String.to_integer(params["expense_account_id"])
        ),
      paid_from_account_id:
        if(params["paid_from_account_id"] && params["paid_from_account_id"] != "",
          do: String.to_integer(params["paid_from_account_id"])
        )
    }

    attrs = if params["amount"], do: %{"amount_cents" => params["amount"]}, else: %{}
    changeset = Expenses.change_expense(prefill, attrs)

    # Pre-populate first split from bill payment query params if present
    initial_splits =
      if params["paid_from_account_id"] && params["paid_from_account_id"] != "" &&
           params["amount"] && params["amount"] != "" do
        [%{"account_id" => params["paid_from_account_id"], "amount_cents" => params["amount"]}]
      else
        []
      end

    render(
      conn,
      :new,
      [
        changeset: changeset,
        action: dp(conn, "/expenses"),
        from_bill: params["from_bill"],
        initial_splits: initial_splits
      ] ++ form_assigns()
    )
  end

  def create(conn, %{"expense" => attrs}) do
    splits = parse_and_convert_splits(attrs)
    attrs = Map.delete(attrs, "splits")

    case Expenses.create_expense_with_splits(attrs, splits) do
      {:ok, expense} ->
        conn
        |> put_flash(:info, "Expense recorded.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :insert)

        render(
          conn,
          :new,
          [
            changeset: changeset,
            action: dp(conn, "/expenses"),
            from_bill: nil,
            initial_splits: splits
          ] ++ form_assigns()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)
    render(conn, :show, expense: expense)
  end

  def edit(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)
    changeset = Expenses.change_expense(expense, %{})

    render(
      conn,
      :edit,
      [expense: expense, changeset: changeset, action: dp(conn, "/expenses/#{expense.id}")] ++
        form_assigns()
    )
  end

  def update(conn, %{"id" => id, "expense" => attrs}) do
    expense = Expenses.get_expense!(id)
    splits = parse_and_convert_splits(attrs)
    attrs = Map.delete(attrs, "splits")

    case Expenses.update_expense_with_splits(expense, attrs, splits) do
      {:ok, expense} ->
        conn
        |> put_flash(:info, "Expense updated.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset = Map.put(changeset, :action, :update)

        render(
          conn,
          :edit,
          [
            expense: expense,
            changeset: changeset,
            action: dp(conn, "/expenses/#{expense.id}"),
            initial_splits: splits
          ] ++ form_assigns()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    expense = Expenses.get_expense!(id)

    case Expenses.delete_expense(expense) do
      {:ok, _} ->
        conn |> put_flash(:info, "Expense deleted.") |> redirect(to: dp(conn, "/expenses"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to delete expense.")
        |> redirect(to: dp(conn, "/expenses/#{expense.id}"))
    end
  end

  defp form_assigns do
    [
      expense_account_options: grouped_expense_account_options(),
      paid_from_account_options: paid_from_options(),
      currency_options: [{"MXN", "MXN"}, {"USD", "USD"}]
    ]
  end

  # Expense account category groups — maps code ranges to parent labels
  @expense_groups [
    {"Auto & Transportation", "6000", "6009"},
    {"Housekeeper & Drivers", "6010", "6019"},
    {"Utilities", "6020", "6029"},
    {"Home & Furniture", "6030", "6039"},
    {"Education", "6040", "6049"},
    {"Entertainment", "6050", "6059"},
    {"Food & Dining", "6060", "6069"},
    {"Health & Personal Care", "6070", "6079"},
    {"Kids", "6080", "6084"},
    {"Shopping", "6085", "6089"},
    {"Travel", "6090", "6094"},
    {"Pets", "6095", "6097"},
    {"Financial & Other", "6098", "6105"}
  ]

  defp grouped_expense_account_options do
    import Ecto.Query
    alias Ledgr.Core.Accounting.Account

    accounts =
      Ledgr.Repo.all(from a in Account, where: a.type == "expense", order_by: a.code)

    Enum.flat_map(@expense_groups, fn {group_label, from_code, to_code} ->
      children =
        Enum.filter(accounts, fn a ->
          a.code >= from_code and a.code <= to_code
        end)

      case children do
        [] ->
          []

        [single] ->
          [{"#{group_label} > #{single.name}", single.id}]

        items ->
          # The first account in each group may be the "parent/general" account
          # (e.g., 6000 "Auto & Transportation" is the catch-all for 600x)
          parent = Enum.find(items, &(&1.code == from_code))

          Enum.map(items, fn a ->
            if parent && a.id == parent.id do
              {"#{group_label} > General / Other", a.id}
            else
              {"#{group_label} > #{a.name}", a.id}
            end
          end)
      end
    end)
  end

  # Parses expense[splits][N][account_id|amount_cents] from form params and converts
  # amount_cents from pesos (string) to integer cents.
  defp parse_and_convert_splits(attrs) do
    case attrs["splits"] do
      nil ->
        []

      splits_map ->
        splits_map
        |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
        |> Enum.map(fn {_, v} -> v end)
        |> Enum.reject(fn s ->
          s["account_id"] == "" or is_nil(s["account_id"]) or
            s["amount_cents"] == "" or is_nil(s["amount_cents"])
        end)
        |> Enum.map(fn s ->
          %{
            "account_id" => s["account_id"],
            "amount_cents" => MoneyHelper.pesos_to_cents(s["amount_cents"])
          }
        end)
    end
  end

  # Only cash, bank, and credit card accounts — no fixed assets, loans, or AP
  # Grouped by currency for clarity
  # Payment account ranges grouped by currency
  # Each entry: {group_label, from_code, to_code, currency}
  @paid_from_ranges [
    {"Cash & Bank", "1000", "1019", "USD"},
    {"Credit Cards", "2000", "2009", "USD"},
    {"Accounts Payable", "2010", "2019", "USD"},
    {"Cash & Bank", "1100", "1119", "MXN"},
    {"Credit Cards", "2100", "2109", "MXN"},
    {"Accounts Payable", "2110", "2119", "MXN"}
  ]

  defp paid_from_options do
    import Ecto.Query
    alias Ledgr.Core.Accounting.Account

    accounts =
      Ledgr.Repo.all(
        from a in Account,
          where:
            (a.code >= "1000" and a.code <= "1019") or
              (a.code >= "1100" and a.code <= "1119") or
              (a.code >= "2000" and a.code <= "2019") or
              (a.code >= "2100" and a.code <= "2119"),
          order_by: [asc: a.code]
      )

    # Build options with data-currency attribute for JS filtering
    Enum.flat_map(@paid_from_ranges, fn {group_label, from_code, to_code, currency} ->
      group_accounts = Enum.filter(accounts, &(&1.code >= from_code and &1.code <= to_code))

      case group_accounts do
        [] ->
          []

        items ->
          Enum.map(items, &{"#{currency}: #{group_label} > #{&1.name}", &1.id})
      end
    end)
  end
end

defmodule LedgrWeb.Domains.CasaTame.ExpenseHTML do
  use LedgrWeb, :html

  embed_templates "expense_html/*"
end
