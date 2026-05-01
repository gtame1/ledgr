defmodule Ledgr.Core.Accounting do
  @moduledoc """
  Accounting context: chart of accounts and double-entry journal.
  """
  import Ecto.Query, warn: false
  # ⬅️ add this
  import Ecto.Changeset

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting.{Account, JournalEntry, JournalLine, MoneyTransfer}
  alias Ledgr.Core.Expenses.Expense
  alias Ledgr.Core.Partners.CapitalContribution

  # ── Account codes used by core accounting functions ─────────────────
  @cash_code "1000"
  @ingredients_inventory_code "1200"
  @packing_inventory_code "1210"
  @kitchen_inventory_code "1300"
  @owners_equity_code "3000"
  @retained_earnings_code "3050"
  @owners_drawings_code "3100"
  @ingredients_cogs_code "5000"
  @packaging_cogs_code "5010"
  @accum_depreciation_code "1310"
  @iva_receivable_code "1400"
  @sales_tax_payable_code "2100"
  @depreciation_expense_code "6045"
  @inventory_waste_code "6060"
  @other_expenses_code "6099"

  @doc """
  Record an inventory purchase:
    - Debit Ingredients Inventory (1200)
    - Credit Cash (1000)

  `total_cost_cents` is the *total* MXN cost in cents.

  `opts` can include:
    - :reference (e.g. "INV-123" or "Purchase FLOUR")
    - :description override
  """
  def record_inventory_purchase(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we’re debiting
    {inv_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) ->
          {get_account_by_code!(@packing_inventory_code), "Packing"}

        Keyword.get(opts, :kitchen, false) ->
          {get_account_by_code!(@kitchen_inventory_code), "Kitchen"}

        true ->
          {get_account_by_code!(@ingredients_inventory_code), "Ingredients"}
      end

    # 2) Decide which account we’re CREDITING (paid from)
    paid_from_account =
      cond do
        # already have an account struct
        acc = Keyword.get(opts, :paid_from_account) ->
          acc

        id = Keyword.get(opts, :paid_from_account_id) ->
          id =
            case id do
              i when is_binary(i) ->
                case Integer.parse(i) do
                  {parsed, _} -> parsed
                  :error -> raise "Invalid paid_from_account_id: #{inspect(id)}"
                end

              i when is_integer(i) ->
                i
            end

          Repo.get!(Ledgr.Core.Accounting.Account, id)

        # passed an account code like "1010"
        code = Keyword.get(opts, :paid_from_account_code) ->
          get_account_by_code!(code)

        # fallback → cash
        true ->
          get_account_by_code!(@cash_code)
      end

    date = Keyword.get(opts, :purchase_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(
        opts,
        :description,
        "#{inventory_type} inventory purchase (paid from #{paid_from_account.code})"
      )

    entry_attrs = %{
      date: date,
      entry_type: "inventory_purchase",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: inv_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "Increase #{inventory_type} inventory"
      },
      %{
        account_id: paid_from_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Paid from #{paid_from_account.code} – #{paid_from_account.name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record an inventory return (reverse of purchase):
    - Credit Ingredients Inventory (1200) - reduces inventory
    - Debit Cash/Account (1000) - refunds the payment

  This is the reverse of `record_inventory_purchase`.
  """
  def record_inventory_return(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we're crediting (reversing the purchase)
    {inv_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) ->
          {get_account_by_code!(@packing_inventory_code), "Packing"}

        Keyword.get(opts, :kitchen, false) ->
          {get_account_by_code!(@kitchen_inventory_code), "Kitchen"}

        true ->
          {get_account_by_code!(@ingredients_inventory_code), "Ingredients"}
      end

    # 2) Decide which account we're DEBITING (refund to)
    paid_from_account =
      cond do
        # already have an account struct
        acc = Keyword.get(opts, :paid_from_account) ->
          acc

        id = Keyword.get(opts, :paid_from_account_id) ->
          id =
            case id do
              i when is_binary(i) ->
                case Integer.parse(i) do
                  {parsed, _} -> parsed
                  :error -> raise "Invalid paid_from_account_id: #{inspect(id)}"
                end

              i when is_integer(i) ->
                i
            end

          Repo.get!(Ledgr.Core.Accounting.Account, id)

        # passed an account code like "1010"
        code = Keyword.get(opts, :paid_from_account_code) ->
          get_account_by_code!(code)

        # fallback → cash
        true ->
          get_account_by_code!(@cash_code)
      end

    date = Keyword.get(opts, :return_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(
        opts,
        :description,
        "#{inventory_type} inventory return (refund to #{paid_from_account.code})"
      )

    entry_attrs = %{
      date: date,
      # Use same type for consistency, or we could add "inventory_return"
      entry_type: "inventory_purchase",
      reference: reference,
      description: description
    }

    # Reverse the purchase: CR Inventory, DR Paid From Account
    lines = [
      %{
        account_id: inv_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Decrease #{inventory_type} inventory (return)"
      },
      %{
        account_id: paid_from_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "Refund to #{paid_from_account.code} – #{paid_from_account.name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record multiple inventory purchases in a single journal entry.
  Creates debit lines for each inventory type (ingredients, packing, kitchen)
  and a single credit line for the total payment.

  Args:
    - total_cost_by_type: %{ingredients: cents, packing: cents, kitchen: cents}
    - opts: keyword list with :purchase_date, :paid_from_account_id, :reference, :description
  """
  def record_multi_inventory_purchase(total_cost_by_type, opts \\ []) do
    # Get the accounts for each inventory type
    ingredients_account = get_account_by_code!(@ingredients_inventory_code)
    packing_account = get_account_by_code!(@packing_inventory_code)
    kitchen_account = get_account_by_code!(@kitchen_inventory_code)

    # Decide which account we're CREDITING (paid from)
    paid_from_account =
      cond do
        acc = Keyword.get(opts, :paid_from_account) ->
          acc

        id = Keyword.get(opts, :paid_from_account_id) ->
          id =
            case id do
              i when is_binary(i) ->
                case Integer.parse(i) do
                  {parsed, _} -> parsed
                  :error -> raise "Invalid paid_from_account_id: #{inspect(id)}"
                end

              i when is_integer(i) ->
                i
            end

          Repo.get!(Account, id)

        code = Keyword.get(opts, :paid_from_account_code) ->
          get_account_by_code!(code)

        true ->
          get_account_by_code!(@cash_code)
      end

    date = Keyword.get(opts, :purchase_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference)
    description = Keyword.get(opts, :description, "Multiple inventory purchases")

    # Build debit lines for each inventory type that has a cost
    lines = []

    lines =
      if total_cost_by_type.ingredients > 0 do
        [
          %{
            account_id: ingredients_account.id,
            debit_cents: total_cost_by_type.ingredients,
            credit_cents: 0,
            description: "Increase Ingredients inventory"
          }
          | lines
        ]
      else
        lines
      end

    lines =
      if total_cost_by_type.packing > 0 do
        [
          %{
            account_id: packing_account.id,
            debit_cents: total_cost_by_type.packing,
            credit_cents: 0,
            description: "Increase Packing inventory"
          }
          | lines
        ]
      else
        lines
      end

    lines =
      if total_cost_by_type.kitchen > 0 do
        [
          %{
            account_id: kitchen_account.id,
            debit_cents: total_cost_by_type.kitchen,
            credit_cents: 0,
            description: "Increase Kitchen inventory"
          }
          | lines
        ]
      else
        lines
      end

    # Calculate total cost for credit line
    total_cost_cents =
      total_cost_by_type.ingredients + total_cost_by_type.packing + total_cost_by_type.kitchen

    # Add single credit line
    lines = [
      %{
        account_id: paid_from_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Paid from #{paid_from_account.code} – #{paid_from_account.name}"
      }
      | lines
    ]

    entry_attrs = %{
      date: date,
      entry_type: "inventory_purchase",
      reference: reference,
      description: description
    }

    create_journal_entry_with_lines(entry_attrs, Enum.reverse(lines))
  end

  @doc """
  Record a partner investment:

    - Debit Cash (1000)
    - Credit Owner's Equity (3000)

  Options:
    - :date (Date)
    - :partner_name (string)
  """
  def record_investment(amount_cents, opts) do
    cash_account_id = Keyword.fetch!(opts, :cash_account_id)
    date = Keyword.get(opts, :date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    partner_name = Keyword.get(opts, :partner_name, "Partner")

    cash_account = Repo.get!(Account, cash_account_id)
    equity_account = get_account_by_code!(@owners_equity_code)

    entry_attrs = %{
      date: date,
      entry_type: "investment",
      reference: "Partner investment",
      description: "Investment from #{partner_name} into #{cash_account.name}"
    }

    lines = [
      %{
        account_id: cash_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Cash received from #{partner_name}"
      },
      %{
        account_id: equity_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Increase in owner's equity (#{partner_name})"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def record_withdrawal(amount_cents, opts) do
    cash_account_id = Keyword.fetch!(opts, :cash_account_id)
    date = Keyword.get(opts, :date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    partner_name = Keyword.get(opts, :partner_name, "Partner")

    cash_account = Repo.get!(Account, cash_account_id)
    # Withdrawals debit Owner's Drawings (contra-equity account)
    # At year-end, Owner's Drawings is closed to Retained Earnings
    owners_drawings = get_account_by_code!(@owners_drawings_code)

    entry_attrs = %{
      date: date,
      entry_type: "withdrawal",
      reference: "Partner withdrawal",
      description: "Withdrawal by #{partner_name} from #{cash_account.name}"
    }

    lines = [
      %{
        account_id: owners_drawings.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Owner's drawing (#{partner_name})"
      },
      %{
        account_id: cash_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Cash paid out to #{partner_name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  # ---------- Accounts ----------

  def list_accounts do
    Repo.all(from a in Account, order_by: [asc: a.code])
  end

  @doc """
  Returns the earliest and latest dates from journal entries.
  Returns {earliest_date, latest_date} or {nil, nil} if no entries exist.
  """
  def journal_entry_date_range do
    result =
      from(je in JournalEntry,
        select: %{
          earliest: fragment("MIN(?)", je.date),
          latest: fragment("MAX(?)", je.date)
        }
      )
      |> Repo.one()

    case result do
      %{earliest: earliest, latest: latest} when not is_nil(earliest) and not is_nil(latest) ->
        {earliest, latest}

      _ ->
        {nil, nil}
    end
  end

  def get_account!(id), do: Repo.get!(Account, id)
  def get_account_by_code(code), do: Repo.get_by(Account, code: code)
  def get_account_by_code!(code), do: Repo.get_by!(Account, code: code)

  @doc """
  Returns a summary of equity account balances for the investments page.
  """
  def get_equity_summary do
    # Get balance for each equity account
    owners_equity_cents = get_account_balance("3000")
    retained_earnings_cents = get_account_balance("3050")
    owners_drawings_cents = get_account_balance("3100")

    # Get current period net income (unclosed)
    last_close_date = get_last_year_end_close_date()
    pnl_start_date = if last_close_date, do: Date.add(last_close_date, 1), else: ~D[2000-01-01]
    pnl = profit_and_loss(pnl_start_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    current_net_income_cents = pnl.net_income_cents

    # Total equity = Owner's Equity + Retained Earnings - Owner's Drawings + Current Net Income
    total_equity_cents =
      owners_equity_cents + retained_earnings_cents - owners_drawings_cents +
        current_net_income_cents

    %{
      owners_equity_cents: owners_equity_cents,
      retained_earnings_cents: retained_earnings_cents,
      owners_drawings_cents: owners_drawings_cents,
      current_net_income_cents: current_net_income_cents,
      total_equity_cents: total_equity_cents,
      last_close_date: last_close_date
    }
  end

  defp get_account_balance(code) do
    account = get_account_by_code(code)

    if account do
      result =
        from(jl in JournalLine,
          join: je in assoc(jl, :journal_entry),
          where: jl.account_id == ^account.id,
          select: %{
            debits: coalesce(sum(jl.debit_cents), 0),
            credits: coalesce(sum(jl.credit_cents), 0)
          }
        )
        |> Repo.one()

      case account.normal_balance do
        "credit" -> (result.credits || 0) - (result.debits || 0)
        "debit" -> (result.debits || 0) - (result.credits || 0)
        _ -> 0
      end
    else
      0
    end
  end

  @doc """
  Returns all vendor AP accounts (codes 2000-2009) with their current balance.
  Excludes credit cards (2011-2014), Sales Tax Payable (2100), and Customer Deposits (2200).

  Returns a list of maps: %{account: %Account{}, balance_cents: integer}
  Positive balance means money is still owed.
  """
  def get_ap_accounts_with_balances do
    ap_accounts =
      Repo.all(
        from a in Account,
          where: a.code >= "2000" and a.code <= "2009",
          order_by: [asc: a.code]
      )

    Enum.map(ap_accounts, fn account ->
      result =
        Repo.one(
          from jl in JournalLine,
            where: jl.account_id == ^account.id,
            select: %{
              debits: coalesce(sum(jl.debit_cents), 0),
              credits: coalesce(sum(jl.credit_cents), 0)
            }
        )

      balance_cents =
        case account.normal_balance do
          "credit" -> (result.credits || 0) - (result.debits || 0)
          "debit" -> (result.debits || 0) - (result.credits || 0)
          _ -> 0
        end

      %{account: account, balance_cents: balance_cents}
    end)
  end

  def create_account(attrs \\ %{}) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  # For select inputs: [{"1000 - Cash", 1}, ...]
  def account_select_options do
    list_accounts()
    |> Enum.map(fn a -> {"#{a.code} - #{a.name}", a.id} end)
  end

  def cash_or_bank_account_options do
    Repo.all(
      from a in Account,
        where: a.type == "asset" and (a.is_cash == true or like(a.name, "%bank%")),
        order_by: a.code
    )
    |> Enum.map(fn a -> {"#{a.code} – #{a.name}", a.id} end)
  end

  def cash_or_payable_account_options do
    Repo.all(
      from a in Account,
        where:
          (a.type == "asset" and (a.is_cash == true or like(a.code, "11%"))) or
            a.type == "liability",
        order_by: [asc: a.code]
    )
    |> Enum.map(fn a ->
      {"#{a.code} – #{a.name}", a.id}
    end)
  end

  # Same as above but returns 3-tuples {label, id, currency} where currency is inferred
  # from the account code prefix. Used by the transfer form to enable same-currency filtering.
  def cash_or_payable_account_options_with_currency do
    Repo.all(
      from a in Account,
        where:
          (a.type == "asset" and (a.is_cash == true or like(a.code, "11%"))) or
            a.type == "liability",
        order_by: [asc: a.code]
    )
    |> Enum.map(fn a ->
      {"#{a.code} – #{a.name}", a.id, infer_account_currency(a.code)}
    end)
  end

  # Infer currency from Casa Tame account code prefix:
  #   10xx, 20xx → USD   |   11xx, 21xx (and others) → MXN
  defp infer_account_currency(code) do
    case String.slice(code, 0, 2) do
      "10" -> "USD"
      "20" -> "USD"
      _ -> "MXN"
    end
  end

  def transfer_account_options do
    from(a in Account,
      where: a.type == "asset",
      order_by: a.code
    )
    |> Repo.all()
    |> Enum.map(fn a ->
      {"#{a.code} – #{a.name}", a.id}
    end)
  end

  # helper to build account select options
  def expense_account_options do
    from(a in Account, where: a.type == "expense", order_by: a.code)
    |> Repo.all()
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  def liability_account_options do
    from(a in Account, where: a.type == "liability", order_by: a.code)
    |> Repo.all()
    |> Enum.map(&{"#{&1.code} – #{&1.name}", &1.id})
  end

  # ---------- Journal entries ----------

  def list_journal_entries do
    Repo.all(
      from e in JournalEntry,
        order_by: [desc: e.date, desc: e.inserted_at]
    )
    |> Repo.preload(journal_lines: [:account])
    |> Enum.map(&put_totals/1)
  end

  def list_recent_journal_entries(limit \\ 5) do
    Repo.all(
      from e in JournalEntry,
        order_by: [desc: e.date, desc: e.inserted_at],
        limit: ^limit
    )
    |> Repo.preload(journal_lines: [:account])
    |> Enum.map(&put_totals/1)
  end

  def get_journal_entry!(id) do
    Repo.get!(JournalEntry, id)
    |> Repo.preload(journal_lines: [:account])
    |> put_totals()
  end

  def list_journal_lines_by_account(account_id, opts \\ []) do
    import Ecto.Query

    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)

    query =
      from jl in JournalLine,
        where: jl.account_id == ^account_id,
        join: je in assoc(jl, :journal_entry),
        join: a in assoc(jl, :account),
        preload: [journal_entry: je, account: a],
        order_by: [desc: je.date, desc: je.inserted_at, desc: jl.id]

    query =
      cond do
        date_from && date_to ->
          from [jl, je] in query,
            where: je.date >= ^date_from and je.date <= ^date_to

        date_from ->
          from [jl, je] in query,
            where: je.date >= ^date_from

        date_to ->
          from [jl, je] in query,
            where: je.date <= ^date_to

        true ->
          query
      end

    Repo.all(query)
  end

  def change_journal_entry(%JournalEntry{} = entry, attrs \\ %{}) do
    JournalEntry.changeset(entry, attrs)
  end

  def create_journal_entry(attrs) do
    %JournalEntry{}
    |> JournalEntry.changeset(attrs)
    |> Repo.insert()
  end

  def create_journal_entry_with_lines(entry_attrs, lines_attrs) do
    line_changesets =
      Enum.map(lines_attrs, fn attrs ->
        JournalLine.changeset(%JournalLine{}, attrs)
      end)

    %JournalEntry{}
    |> JournalEntry.changeset(entry_attrs)
    |> put_assoc(:journal_lines, line_changesets)
    |> Repo.insert()
  end

  def update_journal_entry_with_lines(%JournalEntry{} = entry, entry_attrs, lines_attrs) do
    line_changesets =
      Enum.map(lines_attrs, fn attrs ->
        JournalLine.changeset(%JournalLine{}, attrs)
      end)

    entry
    |> Repo.preload(:journal_lines)
    |> JournalEntry.changeset(entry_attrs)
    |> put_assoc(:journal_lines, line_changesets)
    |> Repo.update()
  end

  # -------- record_expense --------

  @doc """
  Given a persisted %Expense{}, creates an 'expense' journal entry.

  When iva_cents > 0, splits the expense into net + IVA:
    Debit: expense_account (amount_cents - iva_cents)   — net expense
    Debit: IVA Receivable 1400 (iva_cents)              — tax credit
    Credit: paid_from_account (amount_cents)             — total paid

  When iva_cents == 0 (default):
    Debit: expense_account (amount_cents)
    Credit: paid_from_account (amount_cents)
  """
  def record_expense(%Expense{} = expense) do
    iva = expense.iva_cents || 0
    net_cents = expense.amount_cents - iva

    expense_line = %{
      account_id: expense.expense_account_id,
      debit_cents: net_cents,
      credit_cents: 0,
      description: "Expense: #{expense.description}"
    }

    iva_line =
      if iva > 0 do
        iva_account = get_account_by_code!(@iva_receivable_code)

        [
          %{
            account_id: iva_account.id,
            debit_cents: iva,
            credit_cents: 0,
            description: "IVA on expense: #{expense.description}"
          }
        ]
      else
        []
      end

    paid_line = %{
      account_id: expense.paid_from_account_id,
      debit_cents: 0,
      credit_cents: expense.amount_cents,
      description: "Paid from #{describe_account(expense.paid_from_account_id)}"
    }

    lines = [expense_line] ++ iva_line ++ [paid_line]

    entry_attrs = %{
      date: expense.date,
      entry_type: "expense",
      reference: "Expense ##{expense.id}",
      description: expense.description,
      payee: expense.payee
    }

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record inventory write-off (waste/shrinkage) as an expense:

    Dr Inventory Waste & Shrinkage Expense (6060)
    Cr Inventory Account (1200/1210/1300)
  """
  def record_inventory_write_off(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we're crediting
    {inv_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) ->
          {get_account_by_code!(@packing_inventory_code), "Packing"}

        Keyword.get(opts, :kitchen, false) ->
          {get_account_by_code!(@kitchen_inventory_code), "Kitchen"}

        true ->
          {get_account_by_code!(@ingredients_inventory_code), "Ingredients"}
      end

    waste_expense_account = get_account_by_code!(@inventory_waste_code)

    date = Keyword.get(opts, :write_off_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(opts, :description, "#{inventory_type} inventory write-off (waste/shrinkage)")

    entry_attrs = %{
      date: date,
      entry_type: "expense",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: waste_expense_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "Inventory waste: #{inventory_type}"
      },
      %{
        account_id: inv_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Reduce #{inventory_type} inventory"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Record manual inventory usage as COGS (when not part of an order):

    Dr COGS Account (5000/5010)
    Cr Inventory Account (1200/1210/1300)
  """
  def record_inventory_usage(total_cost_cents, opts \\ []) do
    # 1) Decide which inventory account we're crediting and which COGS account to debit
    {inv_account, cogs_account, inventory_type} =
      cond do
        Keyword.get(opts, :packing, false) ->
          {get_account_by_code!(@packing_inventory_code),
           get_account_by_code!(@packaging_cogs_code), "Packing"}

        Keyword.get(opts, :kitchen, false) ->
          # Kitchen equipment is typically not COGS, but expense
          # For now, we'll use Other Expenses for kitchen usage
          {get_account_by_code!(@kitchen_inventory_code),
           get_account_by_code!(@other_expenses_code), "Kitchen"}

        true ->
          {get_account_by_code!(@ingredients_inventory_code),
           get_account_by_code!(@ingredients_cogs_code), "Ingredients"}
      end

    date = Keyword.get(opts, :usage_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference)

    description =
      Keyword.get(opts, :description, "Manual #{inventory_type} inventory usage")

    entry_attrs = %{
      date: date,
      entry_type: "expense",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: cogs_account.id,
        debit_cents: total_cost_cents,
        credit_cents: 0,
        description: "#{inventory_type} used (manual)"
      },
      %{
        account_id: inv_account.id,
        debit_cents: 0,
        credit_cents: total_cost_cents,
        description: "Reduce #{inventory_type} inventory"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def update_expense_journal_entry(%Expense{} = expense) do
    reference = "Expense ##{expense.id}"

    journal_entry =
      from(je in JournalEntry, where: je.reference == ^reference)
      |> Repo.one()

    if journal_entry do
      # Update the journal entry
      entry_attrs = %{
        date: expense.date,
        description: expense.description
      }

      lines = [
        %{
          account_id: expense.expense_account_id,
          debit_cents: expense.amount_cents,
          credit_cents: 0,
          description: "Expense: #{expense.description}"
        },
        %{
          account_id: expense.paid_from_account_id,
          debit_cents: 0,
          credit_cents: expense.amount_cents,
          description: "Paid from #{describe_account(expense.paid_from_account_id)}"
        }
      ]

      update_journal_entry_with_lines(journal_entry, entry_attrs, lines)
    else
      # If journal entry doesn't exist, create it
      record_expense(expense)
    end
  end

  # ---------- Money Transfers ----------

  def create_money_transfer(attrs) do
    form_changeset = change_transfer_form(attrs)

    if form_changeset.valid? do
      %{
        from_account_id: from_id,
        to_account_id: to_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        # 1) Insert the transfer record
        transfer_changeset =
          MoneyTransfer.changeset(%MoneyTransfer{}, %{
            from_account_id: from_id,
            to_account_id: to_id,
            date: date,
            amount_cents: amount_cents,
            note: note
          })

        transfer = Repo.insert!(transfer_changeset)

        # 2) Create the accounting journal entry
        case record_internal_transfer(amount_cents, from_id, to_id,
               date: date,
               note: note,
               reference: "Transfer ##{transfer.id}"
             ) do
          {:ok, _entry} ->
            transfer

          {:error, reason} ->
            IO.inspect(reason, label: "Transfer creation error")
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, transfer} ->
          {:ok, transfer}

        {:error, reason} ->
          {:error,
           form_changeset
           |> Ecto.Changeset.add_error(:base, "Failed to save transfer: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  def list_money_transfers do
    MoneyTransfer
    |> order_by(desc: :date, desc: :inserted_at)
    |> preload([:from_account, :to_account])
    |> Repo.all()
  end

  def get_money_transfer!(id) do
    MoneyTransfer
    |> Repo.get!(id)
    |> Repo.preload([:from_account, :to_account])
  end

  def change_transfer_form(attrs \\ %{}) do
    {%{
       from_account_id: nil,
       to_account_id: nil,
       date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
       amount_pesos: nil,
       note: nil
     },
     %{
       from_account_id: :integer,
       to_account_id: :integer,
       date: :date,
       amount_pesos: :decimal,
       note: :string
     }}
    |> Ecto.Changeset.cast(attrs, [:from_account_id, :to_account_id, :date, :amount_pesos, :note])
    |> Ecto.Changeset.validate_required([
      :from_account_id,
      :to_account_id,
      :date,
      :amount_pesos
    ])
    |> Ecto.Changeset.validate_number(:amount_pesos, greater_than: 0)
    |> validate_different_accounts()
  end

  defp validate_different_accounts(changeset) do
    from_id = Ecto.Changeset.get_field(changeset, :from_account_id)
    to_id = Ecto.Changeset.get_field(changeset, :to_account_id)

    if from_id && to_id && from_id == to_id do
      Ecto.Changeset.add_error(changeset, :to_account_id, "must be different from source account")
    else
      changeset
    end
  end

  def record_internal_transfer(amount_cents, from_account_id, to_account_id, opts \\ []) do
    date = Keyword.get(opts, :date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note = Keyword.get(opts, :note, nil)
    ref = Keyword.get(opts, :reference, nil)

    from_acct = Repo.get!(Account, from_account_id)
    to_acct = Repo.get!(Account, to_account_id)

    if from_acct.id == to_acct.id do
      raise ArgumentError, "cannot transfer within the same account"
    end

    # Allow only asset/liability for this generic internal transfer helper
    allowed_types = ["asset", "liability"]

    unless from_acct.type in allowed_types and to_acct.type in allowed_types do
      raise ArgumentError,
            "record_internal_transfer supports only asset/liability accounts. " <>
              "Use a dedicated accounting function for revenue/expenses/equity."
    end

    description =
      note ||
        "Transfer from #{from_acct.code} #{from_acct.name} " <>
          "to #{to_acct.code} #{to_acct.name}"

    entry_attrs = %{
      date: date,
      entry_type: "internal_transfer",
      reference: ref,
      description: description
    }

    lines = [
      %{
        account_id: to_acct.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Transfer from #{from_acct.code} #{from_acct.name}"
      },
      %{
        account_id: from_acct.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Transfer to #{to_acct.code} #{to_acct.name}"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  def update_money_transfer(%MoneyTransfer{} = transfer, attrs) do
    form_changeset = change_transfer_form(attrs)

    if form_changeset.valid? do
      %{
        from_account_id: from_id,
        to_account_id: to_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        # 1) Find and update the journal entry
        reference = "Transfer ##{transfer.id}"

        journal_entry =
          from(je in JournalEntry, where: je.reference == ^reference)
          |> Repo.one()

        if journal_entry do
          # Update the journal entry
          entry_attrs = %{
            date: date,
            description:
              note || "Transfer from #{describe_account(from_id)} to #{describe_account(to_id)}"
          }

          from_acct = Repo.get!(Account, from_id)
          to_acct = Repo.get!(Account, to_id)

          lines = [
            %{
              account_id: to_acct.id,
              debit_cents: amount_cents,
              credit_cents: 0,
              description: "Transfer from #{from_acct.code} #{from_acct.name}"
            },
            %{
              account_id: from_acct.id,
              debit_cents: 0,
              credit_cents: amount_cents,
              description: "Transfer to #{to_acct.code} #{to_acct.name}"
            }
          ]

          case update_journal_entry_with_lines(journal_entry, entry_attrs, lines) do
            {:ok, _entry} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end

        # 2) Update the transfer record
        transfer_changeset =
          MoneyTransfer.changeset(transfer, %{
            from_account_id: from_id,
            to_account_id: to_id,
            date: date,
            amount_cents: amount_cents,
            note: note
          })

        case Repo.update(transfer_changeset) do
          {:ok, updated_transfer} -> updated_transfer
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> case do
        {:ok, transfer} ->
          {:ok, transfer}

        {:error, reason} ->
          {:error,
           form_changeset
           |> Ecto.Changeset.add_error(:base, "Failed to update transfer: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  def delete_money_transfer(%MoneyTransfer{} = transfer) do
    Repo.transaction(fn ->
      # Find and delete the related journal entry
      reference = "Transfer ##{transfer.id}"

      journal_entry =
        from(je in JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry do
        Repo.delete!(journal_entry)
      end

      # Delete the transfer
      Repo.delete!(transfer)
    end)
  end

  # ---------- Helpers for totals / formatting ----------

  # Adds :total_cents and :total_amount_formatted to entries
  defp put_totals(%JournalEntry{} = entry) do
    total =
      Enum.reduce(entry.journal_lines || [], 0, fn line, acc ->
        acc + (line.debit_cents || 0) - (line.credit_cents || 0)
      end)
      |> abs()

    entry
    |> Map.put(:total_cents, total)
    |> Map.put(:total_amount_formatted, format_cents(total))
  end

  def format_cents(nil), do: "0.00"

  def format_cents(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    pesos = div(cents, 100)

    centavos =
      cents
      |> rem(100)
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    "#{sign}$#{pesos}.#{centavos}"
  end

  defp describe_account(id) do
    case Repo.get(Account, id) do
      nil -> "Account #{id}"
      acc -> "#{acc.code} – #{acc.name}"
    end
  end

  # ---------- Financial Statements ----------

  @doc """
  Profit & Loss for a period.

  Returns a map with:
    - revenue_accounts
    - cogs_accounts
    - operating_expense_accounts
    - total_revenue_cents
    - total_cogs_cents
    - gross_profit_cents
    - total_opex_cents
    - operating_income_cents
    - net_income_cents
  """
  def profit_and_loss(start_date, end_date) do
    # 1) Aggregate debits & credits per account in the period
    query =
      from je in JournalEntry,
        join: jl in assoc(je, :journal_lines),
        join: a in assoc(jl, :account),
        where: je.date >= ^start_date and je.date <= ^end_date,
        group_by: [a.id, a.code, a.name, a.type, a.normal_balance, a.is_cogs],
        select: {
          a.id,
          a.code,
          a.name,
          a.type,
          a.normal_balance,
          a.is_cogs,
          coalesce(sum(jl.debit_cents), 0),
          coalesce(sum(jl.credit_cents), 0)
        }

    rows =
      query
      |> Repo.all()
      |> Enum.map(fn {account_id, code, name, type, normal_balance, is_cogs, debit_cents,
                      credit_cents} ->
        %{
          account_id: account_id,
          code: code,
          name: name,
          type: type,
          normal_balance: normal_balance,
          is_cogs: is_cogs,
          debit_cents: debit_cents,
          credit_cents: credit_cents
        }
      end)

    # 2) Compute net_cents for each account based on normal_balance
    enriched =
      Enum.map(rows, fn row ->
        debits = row.debit_cents || 0
        credits = row.credit_cents || 0

        net =
          case row.normal_balance do
            "debit" -> debits - credits
            "credit" -> credits - debits
            _ -> credits - debits
          end

        Map.put(row, :net_cents, net)
      end)

    # 3) Split by type
    revenue_accounts = Enum.filter(enriched, &(&1.type == "revenue"))
    expense_accounts = Enum.filter(enriched, &(&1.type == "expense"))

    # 4) Split expenses into COGS vs Opex using is_cogs flag
    {cogs_accounts, operating_expense_accounts} =
      Enum.split_with(expense_accounts, fn acc -> acc.is_cogs end)

    # Contra-revenue accounts (like Sales Discounts 4010) have normal_balance "debit"
    # and must be subtracted from total revenue, not added.
    total_revenue_cents =
      Enum.reduce(revenue_accounts, 0, fn acc, sum ->
        if acc.normal_balance == "debit", do: sum - acc.net_cents, else: sum + acc.net_cents
      end)

    total_cogs_cents = Enum.reduce(cogs_accounts, 0, fn acc, sum -> sum + acc.net_cents end)

    total_opex_cents =
      Enum.reduce(operating_expense_accounts, 0, fn acc, sum -> sum + acc.net_cents end)

    gross_profit_cents = total_revenue_cents - total_cogs_cents
    operating_income_cents = gross_profit_cents - total_opex_cents
    net_income_cents = operating_income_cents

    # Calculate margins
    gross_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(gross_profit_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    operating_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(operating_income_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    net_margin_percent =
      if total_revenue_cents > 0 do
        Float.round(net_income_cents / total_revenue_cents * 100, 2)
      else
        0.0
      end

    # Get revenue/COGS breakdown by product from the active domain (if any)
    domain = Ledgr.Domain.current()
    revenue_by_product = if domain, do: domain.revenue_breakdown(start_date, end_date), else: []
    cogs_by_product = if domain, do: domain.cogs_breakdown(start_date, end_date), else: []

    %{
      start_date: start_date,
      end_date: end_date,
      revenue_accounts: revenue_accounts,
      cogs_accounts: cogs_accounts,
      operating_expense_accounts: operating_expense_accounts,
      total_revenue_cents: total_revenue_cents,
      total_cogs_cents: total_cogs_cents,
      gross_profit_cents: gross_profit_cents,
      total_opex_cents: total_opex_cents,
      operating_income_cents: operating_income_cents,
      net_income_cents: net_income_cents,
      gross_margin_percent: gross_margin_percent,
      operating_margin_percent: operating_margin_percent,
      net_margin_percent: net_margin_percent,
      revenue_by_product: revenue_by_product,
      cogs_by_product: cogs_by_product
    }
  end

  def profit_and_loss_monthly(months_back \\ 5) do
    # "months_back = 5" → last 6 months including current
    today = LedgrWeb.Helpers.DomainHelpers.today_mx()
    {year, month, _day} = Date.to_erl(today)

    months =
      0..months_back
      |> Enum.map(fn offset ->
        {y, m} = shift_year_month(year, month, -offset)
        start_date = %Date{year: y, month: m, day: 1}
        end_date = end_of_month(start_date)
        {start_date, end_date}
      end)
      |> Enum.reverse()

    Enum.map(months, fn {start_date, end_date} ->
      summary = profit_and_loss(start_date, end_date)

      # Reuse your summary map and just tag it with a month label + boundaries
      summary
      |> Map.put(:label, "#{start_date.year}-#{pad2(start_date.month)}")
      |> Map.put(:month_start, start_date)
      |> Map.put(:month_end, end_date)
    end)
  end

  # ---- helpers for monthly calc ----

  defp shift_year_month(year, month, delta_months) do
    total = year * 12 + (month - 1) + delta_months
    new_year = div(total, 12)
    new_month = rem(total, 12) + 1
    {new_year, new_month}
  end

  defp end_of_month(%Date{} = date) do
    {y, m, _} = Date.to_erl(date)
    {ny, nm} = shift_year_month(y, m, 1)
    first_next = %Date{year: ny, month: nm, day: 1}
    Date.add(first_next, -1)
  end

  defp pad2(int) when is_integer(int) and int < 10, do: "0#{int}"
  defp pad2(int) when is_integer(int), do: Integer.to_string(int)

  def balance_sheet(as_of_date) do
    # 1) Aggregate balances by account (assets, liabilities, equity)
    # Use a subquery to get only journal lines whose entry is on or before as_of_date,
    # then LEFT JOIN to accounts so zero-balance accounts still appear.
    dated_lines =
      from jl in JournalLine,
        join: je in JournalEntry,
        on: jl.journal_entry_id == je.id,
        where: je.date <= ^as_of_date,
        select: %{
          account_id: jl.account_id,
          debit_cents: jl.debit_cents,
          credit_cents: jl.credit_cents
        }

    rows =
      from a in Account,
        where: a.type in ["asset", "liability", "equity"],
        left_join: dl in subquery(dated_lines),
        on: dl.account_id == a.id,
        group_by: [a.id, a.code, a.name, a.type, a.normal_balance],
        select: %{
          account: a,
          debit_cents: coalesce(sum(dl.debit_cents), 0),
          credit_cents: coalesce(sum(dl.credit_cents), 0)
        }

    base =
      rows
      |> Repo.all()
      |> Enum.reduce(
        %{
          assets: [],
          liabilities: [],
          equity: [],
          total_assets_cents: 0,
          total_liabilities_cents: 0,
          total_equity_cents: 0
        },
        fn %{account: account, debit_cents: debit, credit_cents: credit}, acc ->
          amount_cents =
            case account.normal_balance do
              "debit" -> debit - credit
              "credit" -> credit - debit
              _ -> debit - credit
            end

          case account.type do
            "asset" ->
              %{
                acc
                | assets: acc.assets ++ [%{account: account, amount_cents: amount_cents}],
                  total_assets_cents: acc.total_assets_cents + amount_cents
              }

            "liability" ->
              %{
                acc
                | liabilities:
                    acc.liabilities ++ [%{account: account, amount_cents: amount_cents}],
                  total_liabilities_cents: acc.total_liabilities_cents + amount_cents
              }

            "equity" ->
              # For contra-equity accounts (debit normal balance like Owner's Drawings),
              # their positive balance should REDUCE total equity
              equity_contribution =
                if account.normal_balance == "debit" do
                  # Contra-equity reduces total equity
                  -amount_cents
                else
                  # Normal equity increases total equity
                  amount_cents
                end

              %{
                acc
                | equity: acc.equity ++ [%{account: account, amount_cents: amount_cents}],
                  total_equity_cents: acc.total_equity_cents + equity_contribution
              }
          end
        end
      )

    # 2) Compute Net Income - only for the current (unclosed) period
    # If there's a year-end close entry, start P&L from the day after the close date
    last_close_date = get_last_year_end_close_date()
    pnl_start_date = if last_close_date, do: Date.add(last_close_date, 1), else: ~D[2000-01-01]

    pnl = profit_and_loss(pnl_start_date, as_of_date)
    net_income_cents = pnl.net_income_cents

    # 3) Compute RHS: Liabilities + Equity + Net Income
    rhs_total_cents =
      base.total_liabilities_cents +
        base.total_equity_cents +
        net_income_cents

    balance_diff_cents = base.total_assets_cents - rhs_total_cents

    base
    |> Map.put(:net_income_cents, net_income_cents)
    |> Map.put(:liabilities_plus_equity_plus_income_cents, rhs_total_cents)
    |> Map.put(:balance_diff_cents, balance_diff_cents)
    |> Map.put(:last_close_date, last_close_date)
  end

  @doc """
  Returns the date of the most recent year-end close entry, or nil if none exists.
  """
  def get_last_year_end_close_date do
    from(je in JournalEntry,
      where: je.entry_type == "year_end_close",
      order_by: [desc: je.date],
      limit: 1,
      select: je.date
    )
    |> Repo.one()
  end

  @doc """
  Performs a year-end close by transferring net income to Retained Earnings.

  Creates a journal entry that:
  - Credits Retained Earnings for the net income amount (or debits if loss)
  - Uses the specified close_date as the entry date

  Returns {:ok, journal_entry} or {:error, reason}
  """
  def close_year_end(close_date) do
    # Check if already closed for this date
    existing =
      from(je in JournalEntry,
        where: je.entry_type == "year_end_close" and je.date == ^close_date,
        select: je.id
      )
      |> Repo.one()

    if existing do
      {:error, "Year-end close already exists for #{close_date}"}
    else
      # Calculate net income from last close (or all time) through close_date
      last_close = get_last_year_end_close_date()
      start_date = if last_close, do: Date.add(last_close, 1), else: ~D[2000-01-01]

      pnl = profit_and_loss(start_date, close_date)

      # Get Owner's Drawings balance for the period
      owners_drawings_balance = get_owners_drawings_balance(start_date, close_date)

      # Get all revenue and expense account balances for the period
      temp_account_balances = get_temporary_account_balances(start_date, close_date)

      has_activity = pnl.net_income_cents != 0 or owners_drawings_balance != 0

      if !has_activity do
        {:ok, :nothing_to_close}
      else
        retained_earnings = get_account_by_code!(@retained_earnings_code)
        owners_drawings_account = get_account_by_code!(@owners_drawings_code)

        entry_attrs = %{
          date: close_date,
          entry_type: "year_end_close",
          reference: "Year-End Close #{close_date.year}",
          description:
            "Close #{close_date.year} net income and owner's drawings to retained earnings"
        }

        lines = []

        # Close each revenue account (debit to zero out credit balances)
        lines =
          Enum.reduce(temp_account_balances, lines, fn
            %{type: "revenue", account_id: acc_id, net_cents: net, name: name}, acc
            when net != 0 ->
              # Revenue has credit-normal balance; debit to close it
              acc ++
                [
                  %{
                    account_id: acc_id,
                    debit_cents: max(net, 0),
                    credit_cents: max(-net, 0),
                    description: "Close #{name} to retained earnings"
                  }
                ]

            %{type: "expense", account_id: acc_id, net_cents: net, name: name}, acc
            when net != 0 ->
              # Expense has debit-normal balance; credit to close it
              acc ++
                [
                  %{
                    account_id: acc_id,
                    debit_cents: max(-net, 0),
                    credit_cents: max(net, 0),
                    description: "Close #{name} to retained earnings"
                  }
                ]

            _, acc ->
              acc
          end)

        # Close Owner's Drawings (credit to zero out debit balance)
        lines =
          if owners_drawings_balance > 0 do
            lines ++
              [
                %{
                  account_id: owners_drawings_account.id,
                  debit_cents: 0,
                  credit_cents: owners_drawings_balance,
                  description: "Close owner's drawings to retained earnings"
                }
              ]
          else
            lines
          end

        # Retained Earnings gets the balancing amount
        # Net amount = Net Income - Owner's Drawings
        amount_to_close = pnl.net_income_cents - owners_drawings_balance

        lines =
          if amount_to_close >= 0 do
            lines ++
              [
                %{
                  account_id: retained_earnings.id,
                  debit_cents: 0,
                  credit_cents: amount_to_close,
                  description: "Net income closed to retained earnings"
                }
              ]
          else
            lines ++
              [
                %{
                  account_id: retained_earnings.id,
                  debit_cents: abs(amount_to_close),
                  credit_cents: 0,
                  description: "Net loss closed to retained earnings"
                }
              ]
          end

        create_journal_entry_with_lines(entry_attrs, lines)
      end
    end
  end

  # Get balances for all revenue and expense accounts in a period.
  # Uses inner joins (same pattern as profit_and_loss) so only lines
  # with entries in the date range are included.
  defp get_temporary_account_balances(start_date, end_date) do
    from(je in JournalEntry,
      join: jl in assoc(je, :journal_lines),
      join: a in assoc(jl, :account),
      where: a.type in ["revenue", "expense"],
      where: je.date >= ^start_date and je.date <= ^end_date,
      where: je.entry_type != "year_end_close",
      group_by: [a.id, a.code, a.name, a.type],
      select: %{
        account_id: a.id,
        code: a.code,
        name: a.name,
        type: a.type,
        debit_cents: coalesce(sum(jl.debit_cents), 0),
        credit_cents: coalesce(sum(jl.credit_cents), 0)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      net =
        case row.type do
          "revenue" -> row.credit_cents - row.debit_cents
          "expense" -> row.debit_cents - row.credit_cents
          _ -> 0
        end

      Map.put(row, :net_cents, net)
    end)
  end

  # Get the debit balance of Owner's Drawings for a period
  defp get_owners_drawings_balance(start_date, end_date) do
    owners_drawings = get_account_by_code(@owners_drawings_code)

    if owners_drawings do
      result =
        from(je in JournalEntry,
          join: jl in assoc(je, :journal_lines),
          where:
            jl.account_id == ^owners_drawings.id and
              je.date >= ^start_date and je.date <= ^end_date,
          select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
        )
        |> Repo.one()

      result || 0
    else
      0
    end
  end

  # ---------- Capital Contributions ----------

  def record_capital_contribution(%CapitalContribution{} = contrib) do
    contrib = Repo.preload(contrib, [:partner, :cash_account])

    cash_account =
      case contrib.cash_account do
        %Account{} = acc -> acc
        # fallback, just in case
        _ -> get_account_by_code!(@cash_code)
      end

    equity_account = get_account_by_code!(@owners_equity_code)
    amount = contrib.amount_cents

    case contrib.direction do
      "in" ->
        record_owner_investment(contrib, cash_account, equity_account, amount)

      "out" ->
        # Withdrawals must debit Owner's Drawings (contra-equity), not Owner's Equity directly.
        # Owner's Drawings is closed to Retained Earnings at year-end.
        drawings_account = get_account_by_code!(@owners_drawings_code)
        record_owner_withdrawal(contrib, cash_account, drawings_account, amount)

      _ ->
        {:error, :unknown_direction}
    end
  end

  defp record_owner_investment(contrib, cash_account, equity_account, amount_cents) do
    entry_attrs = %{
      date: contrib.date,
      entry_type: "investment",
      reference: "Capital contribution ##{contrib.id}",
      description:
        contrib.note ||
          "Owner investment by #{(contrib.partner && contrib.partner.name) || "Partner"}"
    }

    lines = [
      %{
        account_id: cash_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Cash received from partner"
      },
      %{
        account_id: equity_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Increase in owner's equity"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  defp record_owner_withdrawal(contrib, cash_account, equity_account, amount_cents) do
    entry_attrs = %{
      date: contrib.date,
      entry_type: "withdrawal",
      reference: "Capital withdrawal ##{contrib.id}",
      description:
        contrib.note ||
          "Owner withdrawal by #{(contrib.partner && contrib.partner.name) || "Partner"}"
    }

    lines = [
      %{
        account_id: equity_account.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Owner's drawings (withdrawal)"
      },
      %{
        account_id: cash_account.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Cash paid to partner"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  # ── Depreciation ──────────────────────────────────────────────────────

  @doc """
  Record monthly straight-line depreciation for kitchen equipment.

  Creates a journal entry:
    Dr Depreciation Expense (6045)
    Cr Accumulated Depreciation - Equipment (1310)

  Parameters:
    - amount_cents: monthly depreciation amount
    - opts:
      - :date - date of the entry (defaults to today)
      - :reference - reference string
      - :description - custom description
  """
  def record_depreciation(amount_cents, opts \\ []) do
    depreciation_expense = get_account_by_code!(@depreciation_expense_code)
    accum_depreciation = get_account_by_code!(@accum_depreciation_code)

    date = Keyword.get(opts, :date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    reference = Keyword.get(opts, :reference, "Monthly depreciation")

    description =
      Keyword.get(opts, :description, "Monthly straight-line depreciation - Kitchen Equipment")

    entry_attrs = %{
      date: date,
      entry_type: "depreciation",
      reference: reference,
      description: description
    }

    lines = [
      %{
        account_id: depreciation_expense.id,
        debit_cents: amount_cents,
        credit_cents: 0,
        description: "Depreciation expense"
      },
      %{
        account_id: accum_depreciation.id,
        debit_cents: 0,
        credit_cents: amount_cents,
        description: "Accumulated depreciation - Equipment"
      }
    ]

    create_journal_entry_with_lines(entry_attrs, lines)
  end

  @doc """
  Calculate monthly depreciation amount for kitchen equipment using straight-line method.

  Parameters:
    - useful_life_months: total useful life in months (e.g., 60 for 5 years)

  Returns the monthly depreciation amount in cents, or 0 if no equipment exists.
  """
  def calculate_monthly_depreciation(useful_life_months) do
    equipment_account = get_account_by_code!(@kitchen_inventory_code)
    accum_depr_account = get_account_by_code!(@accum_depreciation_code)

    # Get gross equipment cost (debit balance of 1300)
    gross_cost =
      from(jl in JournalLine,
        join: je in JournalEntry,
        on: jl.journal_entry_id == je.id,
        where: jl.account_id == ^equipment_account.id,
        select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    # Get accumulated depreciation so far (credit balance of 1310)
    accum_depr =
      from(jl in JournalLine,
        join: je in JournalEntry,
        on: jl.journal_entry_id == je.id,
        where: jl.account_id == ^accum_depr_account.id,
        select: coalesce(sum(jl.credit_cents), 0) - coalesce(sum(jl.debit_cents), 0)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        total -> total
      end

    remaining = gross_cost - accum_depr

    if remaining > 0 and useful_life_months > 0 do
      # Monthly depreciation = gross cost / useful life
      # (Not remaining / remaining life, since straight-line uses original cost)
      div(gross_cost, useful_life_months)
    else
      0
    end
  end

  # ------- IVA / VAT POSITION -------

  @doc """
  Calculate the net IVA position as of the given date.

  Returns a map with:
  - iva_receivable_cents:  debit balance of 1400 (IVA paid on purchases)
  - iva_payable_cents:     credit balance of 2100 (IVA collected on sales)
  - net_position_cents:    receivable - payable (positive = net credit, negative = net payable)
  """
  def iva_position(as_of_date \\ LedgrWeb.Helpers.DomainHelpers.today_mx()) do
    iva_receivable_account = get_account_by_code!(@iva_receivable_code)
    iva_payable_account = get_account_by_code!(@sales_tax_payable_code)

    receivable =
      from(jl in JournalLine,
        join: je in JournalEntry,
        on: jl.journal_entry_id == je.id,
        where: jl.account_id == ^iva_receivable_account.id and je.date <= ^as_of_date,
        select: coalesce(sum(jl.debit_cents), 0) - coalesce(sum(jl.credit_cents), 0)
      )
      |> Repo.one() || 0

    payable =
      from(jl in JournalLine,
        join: je in JournalEntry,
        on: jl.journal_entry_id == je.id,
        where: jl.account_id == ^iva_payable_account.id and je.date <= ^as_of_date,
        select: coalesce(sum(jl.credit_cents), 0) - coalesce(sum(jl.debit_cents), 0)
      )
      |> Repo.one() || 0

    %{
      as_of_date: as_of_date,
      iva_receivable_cents: receivable,
      iva_payable_cents: payable,
      net_position_cents: receivable - payable
    }
  end
end
