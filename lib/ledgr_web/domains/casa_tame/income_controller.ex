defmodule LedgrWeb.Domains.CasaTame.IncomeController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.CasaTame.Income
  alias Ledgr.Domains.CasaTame.Income.IncomeEntry
  alias Ledgr.Domains.CasaTame.Categories
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, params) do
    entries = Income.list_income_entries(
      currency: params["currency"],
      category_id: params["category_id"],
      date_from: params["date_from"],
      date_to: params["date_to"]
    )

    render(conn, :index,
      entries: entries,
      currency_filter: params["currency"] || "",
      category_filter: params["category_id"] || "",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || "",
      category_options: Categories.income_category_options()
    )
  end

  def new(conn, _params) do
    changeset = Income.change_income_entry(%IncomeEntry{date: Ledgr.Domains.CasaTame.today(), currency: "MXN"})
    render(conn, :new, [changeset: changeset, action: dp(conn, "/income")] ++ form_assigns())
  end

  def create(conn, %{"income_entry" => attrs}) do
    attrs = MoneyHelper.convert_params_pesos_to_cents(attrs, [:amount_cents])

    case Income.create_income_entry_with_journal(attrs) do
      {:ok, entry} ->
        conn |> put_flash(:info, "Income recorded.") |> redirect(to: dp(conn, "/income/#{entry.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset =
          changeset
          |> Map.put(:action, :insert)
          |> Ecto.Changeset.put_change(:amount_cents,
               MoneyHelper.cents_to_pesos(Ecto.Changeset.get_field(changeset, :amount_cents)))

        render(conn, :new, [changeset: changeset, action: dp(conn, "/income")] ++ form_assigns())
    end
  end

  def show(conn, %{"id" => id}) do
    entry = Income.get_income_entry!(id)
    render(conn, :show, entry: entry)
  end

  def edit(conn, %{"id" => id}) do
    entry = Income.get_income_entry!(id)
    attrs = %{"amount_cents" => MoneyHelper.cents_to_pesos(entry.amount_cents)}
    changeset = Income.change_income_entry(entry, attrs)

    render(conn, :edit,
      [entry: entry, changeset: changeset, action: dp(conn, "/income/#{entry.id}")] ++ form_assigns()
    )
  end

  def update(conn, %{"id" => id, "income_entry" => attrs}) do
    entry = Income.get_income_entry!(id)
    attrs = MoneyHelper.convert_params_pesos_to_cents(attrs, [:amount_cents])

    case Income.update_income_entry_with_journal(entry, attrs) do
      {:ok, entry} ->
        conn |> put_flash(:info, "Income updated.") |> redirect(to: dp(conn, "/income/#{entry.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        changeset =
          changeset
          |> Map.put(:action, :update)
          |> Ecto.Changeset.put_change(:amount_cents,
               MoneyHelper.cents_to_pesos(Ecto.Changeset.get_field(changeset, :amount_cents)))

        render(conn, :edit,
          [entry: entry, changeset: changeset, action: dp(conn, "/income/#{entry.id}")] ++ form_assigns()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    entry = Income.get_income_entry!(id)

    case Income.delete_income_entry(entry) do
      {:ok, _} -> conn |> put_flash(:info, "Income deleted.") |> redirect(to: dp(conn, "/income"))
      {:error, _} -> conn |> put_flash(:error, "Failed to delete.") |> redirect(to: dp(conn, "/income/#{entry.id}"))
    end
  end

  defp form_assigns do
    [
      category_options: Categories.income_category_options(),
      deposit_account_options: deposit_options(),
      currency_options: [{"MXN", "MXN"}, {"USD", "USD"}]
    ]
  end

  # Deposit accounts grouped by currency for JS filtering
  @deposit_ranges [
    {"Cash & Bank", "1000", "1019", "USD"},
    {"Cash & Bank", "1100", "1119", "MXN"}
  ]

  defp deposit_options do
    import Ecto.Query
    alias Ledgr.Core.Accounting.Account

    accounts =
      Ledgr.Repo.all(
        from a in Account,
          where: (a.code >= "1000" and a.code <= "1019")
              or (a.code >= "1100" and a.code <= "1119"),
          order_by: [asc: a.code]
      )

    Enum.flat_map(@deposit_ranges, fn {_group_label, from_code, to_code, currency} ->
      group_accounts = Enum.filter(accounts, fn a -> a.code >= from_code and a.code <= to_code end)
      Enum.map(group_accounts, fn a -> {"#{currency}: #{a.name}", a.id} end)
    end)
  end
end

defmodule LedgrWeb.Domains.CasaTame.IncomeHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "income_html/*"
end
