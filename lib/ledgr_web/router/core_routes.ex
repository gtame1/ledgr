defmodule LedgrWeb.Router.CoreRoutes do
  @moduledoc """
  Macro that expands the core (shared) routes for every domain scope.

  These routes are included under each `/app/:domain/` scope so that
  every domain gets its own set of core accounting, reporting, and
  management routes.

  Usage in the router:

      import LedgrWeb.Router.CoreRoutes

      scope "/app/mr-munch-me", LedgrWeb do
        pipe_through :browser
        core_routes()
      end
  """

  @doc """
  Same as `core_routes/0` but skips the customers resource.
  Use in domain scopes that manage their own customer controller.
  """
  defmacro core_routes_no_customers do
    quote do
      unquote(shared_routes())
    end
  end

  defmacro core_routes do
    quote do
      unquote(shared_routes())
      # Customers
      resources "/customers", CustomerController
    end
  end

  @doc """
  Core routes for personal finance domains.
  Includes accounting, reporting, reconciliation, and transfers but
  excludes customers, expenses (overridden by domain), investments
  (partner-style), AP summary, and unit economics.
  """
  defmacro core_routes_personal_finance do
    quote do
      # Dashboard (root of each domain scope)
      get "/", ReportController, :dashboard

      # Transactions (manual journal entries)
      resources "/transactions", TransactionController, only: [:index, :new, :create, :show]
      get "/account-transactions", AccountTransactionController, :index

      # Reports (core financial statements only)
      get "/reports/pnl", ReportController, :pnl
      get "/reports/balance_sheet", ReportController, :balance_sheet

      # Reconciliation
      get "/reconciliation/accounting", ReconciliationController, :accounting_index
      post "/reconciliation/accounting/adjust", ReconciliationController, :accounting_adjust
      post "/reconciliation/accounting/reconcile_all", ReconciliationController, :accounting_reconcile_all

      # Transfers
      resources "/transfers", TransferController
    end
  end

  defp shared_routes do
    quote do
      # Dashboard (root of each domain scope)
      get "/", ReportController, :dashboard

      # Transactions
      resources "/transactions", TransactionController, only: [:index, :new, :create, :show]
      get "/account-transactions", AccountTransactionController, :index

      # Reports
      get "/reports/pnl", ReportController, :pnl
      get "/reports/balance_sheet", ReportController, :balance_sheet
      post "/reports/year_end_close", ReportController, :year_end_close
      get "/reports/unit_economics", ReportController, :unit_economics
      get "/reports/unit_economics_list", ReportController, :unit_economics_list
      get "/reports/cash_flow", ReportController, :cash_flow
      get "/reports/financial_analysis", ReportController, :financial_analysis
      get "/reports/ap_summary", ReportController, :ap_summary

      # Reconciliation (accounting only — inventory is MrMunchMe-specific)
      get "/reconciliation/accounting", ReconciliationController, :accounting_index
      post "/reconciliation/accounting/adjust", ReconciliationController, :accounting_adjust
      post "/reconciliation/accounting/reconcile_all", ReconciliationController, :accounting_reconcile_all

      # Investments
      get "/investments", InvestmentController, :index
      get "/investments/new", InvestmentController, :new
      get "/investments/withdrawal", InvestmentController, :new_withdrawal
      post "/investments", InvestmentController, :create
      post "/investments/create-withdrawal", InvestmentController, :create_withdrawal

      # Transfers
      resources "/transfers", TransferController

      # Expenses
      resources "/expenses", ExpenseController, only: [:index, :new, :create, :show, :edit, :update, :delete]
    end
  end
end
