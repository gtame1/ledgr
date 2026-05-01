defmodule Mix.Tasks.ResetAllTables do
  use Mix.Task

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting.{Account, JournalEntry, JournalLine, MoneyTransfer}

  alias Ledgr.Domains.MrMunchMe.Inventory.{
    InventoryItem,
    InventoryMovement,
    Ingredient,
    Location,
    Recipe,
    RecipeLine
  }

  alias Ledgr.Domains.MrMunchMe.Orders.{Order, Product, OrderPayment}
  alias Ledgr.Core.Partners.{Partner, CapitalContribution}
  alias Ledgr.Core.Expenses.Expense

  @shortdoc "Deletes data from all main tables"

  def run(_args) do
    Mix.Task.run("app.start")

    Repo.transaction(fn ->
      # 1) Children that depend on others
      Repo.delete_all(Expense)
      Repo.delete_all(OrderPayment)
      Repo.delete_all(JournalLine)
      Repo.delete_all(JournalEntry)
      Repo.delete_all(InventoryMovement)
      Repo.delete_all(InventoryItem)
      Repo.delete_all(CapitalContribution)
      Repo.delete_all(MoneyTransfer)
      # Depends on Recipe
      Repo.delete_all(RecipeLine)

      # 2) Mid-level dependents
      # Depends on Product, must be deleted before Product
      Repo.delete_all(Recipe)
      Repo.delete_all(Order)
      Repo.delete_all(Product)
      Repo.delete_all(Ingredient)
      Repo.delete_all(Location)
      Repo.delete_all(Partner)

      # 3) Root tables
      Repo.delete_all(Account)
    end)
  end
end
