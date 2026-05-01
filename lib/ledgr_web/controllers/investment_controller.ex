defmodule LedgrWeb.InvestmentController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Partners
  alias Ledgr.Core.Accounting

  def index(conn, _params) do
    partner_totals = Partners.list_partners_with_totals()
    total_invested = Partners.total_invested_cents()
    recent_contributions = Partners.list_recent_contributions()

    # Get equity account balances from accounting
    equity_summary = Accounting.get_equity_summary()

    render(conn, :index,
      partner_totals: partner_totals,
      total_invested_cents: total_invested,
      recent_contributions: recent_contributions,
      equity_summary: equity_summary
    )
  end

  def new(conn, _params) do
    changeset = Partners.change_contribution_form(%{})

    partner_options =
      Partners.list_partners()
      |> Enum.map(&{&1.name, &1.id})

    cash_account_options = Accounting.cash_or_bank_account_options()

    render(conn, :new,
      changeset: changeset,
      partner_options: partner_options,
      cash_account_options: cash_account_options
    )
  end

  def new_withdrawal(conn, _params) do
    changeset = Partners.change_contribution_form(%{})

    partner_options =
      Partners.list_partners()
      |> Enum.map(&{&1.name, &1.id})

    cash_account_options = Accounting.cash_or_bank_account_options()

    render(conn, :new_withdrawal,
      changeset: changeset,
      partner_options: partner_options,
      cash_account_options: cash_account_options
    )
  end

  def create(conn, %{"contribution" => contrib_params}) do
    case Partners.create_contribution(contrib_params) do
      {:ok, _contribution} ->
        conn
        |> put_flash(:info, "Investment recorded successfully.")
        |> redirect(to: dp(conn, "/investments"))

      {:error, changeset} ->
        partner_options =
          Partners.list_partners()
          |> Enum.map(&{&1.name, &1.id})

        cash_account_options = Accounting.cash_or_bank_account_options()

        render(conn, :new,
          changeset: changeset,
          partner_options: partner_options,
          cash_account_options: cash_account_options
        )
    end
  end

  def create_withdrawal(conn, %{"withdrawal" => withdrawal_params}) do
    case Partners.create_withdrawal(withdrawal_params) do
      {:ok, _withdrawal} ->
        conn
        |> put_flash(:info, "Withdrawal recorded successfully.")
        |> redirect(to: dp(conn, "/investments"))

      {:error, changeset} ->
        partner_options =
          Partners.list_partners()
          |> Enum.map(&{&1.name, &1.id})

        cash_account_options = Accounting.cash_or_bank_account_options()

        render(conn, :new_withdrawal,
          changeset: changeset,
          partner_options: partner_options,
          cash_account_options: cash_account_options
        )
    end
  end
end

defmodule LedgrWeb.InvestmentHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "investment_html/*"
end
