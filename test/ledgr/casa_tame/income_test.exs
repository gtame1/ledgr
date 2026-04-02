defmodule Ledgr.Domains.CasaTame.IncomeTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.CasaTame.Income
  alias Ledgr.Domains.CasaTame.Income.IncomeEntry
  alias Ledgr.Domains.CasaTame.Categories
  alias Ledgr.Core.Accounting
  alias Ledgr.Repo

  import Ecto.Query

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.CasaTame)
    Ledgr.Domain.put_current(Ledgr.Domains.CasaTame)
    casa_tame_accounts_fixture()
    :ok
  end

  # ── Fixtures ────────────────────────────────────────────────────────────

  defp casa_tame_accounts_fixture do
    accounts = [
      %{code: "1000", name: "Cash USD",          type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "1010", name: "Checking USD",      type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "1100", name: "Cash MXN",          type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "1110", name: "Checking MXN",      type: "asset",   normal_balance: "debit",  is_cash: true},
      %{code: "3000", name: "Owner's Equity",    type: "equity",  normal_balance: "credit", is_cash: false},
      %{code: "3050", name: "Retained Earnings", type: "equity",  normal_balance: "credit", is_cash: false},
      %{code: "4000", name: "Wages USD",         type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4010", name: "Wages MXN",         type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4020", name: "Freelance",         type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4030", name: "Investment Returns", type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4040", name: "Rental Income",     type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "4050", name: "Other Income",      type: "revenue", normal_balance: "credit", is_cash: false},
      %{code: "6000", name: "Housing",           type: "expense", normal_balance: "debit",  is_cash: false}
    ]

    Enum.each(accounts, fn attrs ->
      case Accounting.get_account_by_code(attrs.code) do
        nil -> {:ok, _} = Accounting.create_account(attrs)
        _ -> :ok
      end
    end)
  end

  defp deposit_account, do: Accounting.get_account_by_code!("1000")
  defp mxn_deposit_account, do: Accounting.get_account_by_code!("1100")

  defp income_attrs(overrides \\ %{}) do
    Enum.into(overrides, %{
      date: ~D[2026-01-15],
      description: "Salary #{System.unique_integer([:positive])}",
      amount_cents: 200_000,
      currency: "MXN",
      deposit_account_id: mxn_deposit_account().id
    })
  end

  defp income_fixture(overrides \\ %{}) do
    {:ok, entry} = Income.create_income_entry_with_journal(income_attrs(overrides))
    entry
  end

  defp income_category_fixture(name \\ nil) do
    name = name || "Cat #{System.unique_integer([:positive])}"
    {:ok, cat} = Categories.create_expense_category(%{name: name})
    # IncomeCategory doesn't go through Categories module — insert directly
    Repo.insert!(%Ledgr.Domains.CasaTame.Categories.IncomeCategory{name: name})
  end

  # ── list_income_entries/1 ───────────────────────────────────────────────

  describe "list_income_entries/1" do
    test "returns all entries with associations preloaded" do
      entry = income_fixture()
      found = Enum.find(Income.list_income_entries(), &(&1.id == entry.id))
      assert found != nil
      assert %Accounting.Account{} = found.deposit_account
    end

    test "returns empty list when no entries exist" do
      assert Income.list_income_entries() == []
    end

    test "orders by date descending" do
      income_fixture(%{date: ~D[2026-01-01]})
      income_fixture(%{date: ~D[2026-03-01]})

      dates = Income.list_income_entries() |> Enum.map(& &1.date)
      assert dates == Enum.sort(dates, {:desc, Date})
    end

    test "filters by currency" do
      income_fixture(%{currency: "MXN"})
      income_fixture(%{currency: "USD", deposit_account_id: deposit_account().id})

      mxn = Income.list_income_entries(currency: "MXN")
      usd = Income.list_income_entries(currency: "USD")

      assert Enum.all?(mxn, &(&1.currency == "MXN"))
      assert Enum.all?(usd, &(&1.currency == "USD"))
    end

    test "filters by date range" do
      income_fixture(%{date: ~D[2026-01-10]})
      income_fixture(%{date: ~D[2026-03-10]})

      results = Income.list_income_entries(date_from: ~D[2026-03-01], date_to: ~D[2026-03-31])
      assert Enum.all?(results, &(&1.date >= ~D[2026-03-01]))
    end

    test "filters by date range given as strings" do
      income_fixture(%{date: ~D[2026-02-14]})

      results = Income.list_income_entries(date_from: "2026-02-01", date_to: "2026-02-28")
      assert Enum.all?(results, &(&1.date >= ~D[2026-02-01]))
    end

    test "empty string filter is ignored" do
      income_fixture()
      assert Income.list_income_entries(currency: "") |> length() >= 1
    end
  end

  # ── get_income_entry!/1 ─────────────────────────────────────────────────

  describe "get_income_entry!/1" do
    test "returns entry with associations preloaded" do
      entry = income_fixture()
      found = Income.get_income_entry!(entry.id)
      assert found.id == entry.id
      assert %Accounting.Account{} = found.deposit_account
    end

    test "raises Ecto.NoResultsError for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Income.get_income_entry!(0)
      end
    end
  end

  # ── change_income_entry/2 ───────────────────────────────────────────────

  describe "change_income_entry/2" do
    test "returns a changeset for an existing entry" do
      entry = income_fixture()
      assert %Ecto.Changeset{} = Income.change_income_entry(entry, %{description: "Updated"})
    end

    test "returns a changeset for a new struct" do
      assert %Ecto.Changeset{} = Income.change_income_entry(%IncomeEntry{})
    end
  end

  # ── create_income_entry_with_journal/1 ─────────────────────────────────

  describe "create_income_entry_with_journal/1" do
    test "persists entry with correct fields" do
      attrs = income_attrs(%{description: "Freelance payment", amount_cents: 500_000})
      assert {:ok, %IncomeEntry{} = entry} = Income.create_income_entry_with_journal(attrs)
      assert entry.description == "Freelance payment"
      assert entry.amount_cents == 500_000
      assert entry.currency == "MXN"
    end

    test "creates an associated journal entry" do
      {:ok, entry} = Income.create_income_entry_with_journal(income_attrs())
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry, where: j.reference == ^reference)
      assert je != nil
      assert je.entry_type == "income"
    end

    test "creates journal entry with correct debit/credit lines" do
      {:ok, entry} = Income.create_income_entry_with_journal(income_attrs(%{amount_cents: 300_000}))
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )

      debit_line = Enum.find(je.journal_lines, &(&1.debit_cents == 300_000))
      credit_line = Enum.find(je.journal_lines, &(&1.credit_cents == 300_000))

      assert debit_line.account_id == entry.deposit_account_id
      assert credit_line != nil
    end

    test "returns error changeset for missing required fields" do
      assert {:error, %Ecto.Changeset{}} = Income.create_income_entry_with_journal(%{})
    end

    test "returns error for zero amount" do
      assert {:error, _} = Income.create_income_entry_with_journal(income_attrs(%{amount_cents: 0}))
    end

    test "returns error for invalid currency" do
      assert {:error, _} = Income.create_income_entry_with_journal(income_attrs(%{currency: "GBP"}))
    end

    test "accepts USD currency" do
      assert {:ok, entry} = Income.create_income_entry_with_journal(
        income_attrs(%{currency: "USD", deposit_account_id: deposit_account().id})
      )
      assert entry.currency == "USD"
    end

    test "resolves wages USD revenue account for Wages & Salary category in USD" do
      cat = income_category_fixture("Wages & Salary")
      {:ok, entry} = Income.create_income_entry_with_journal(
        income_attrs(%{currency: "USD", deposit_account_id: deposit_account().id, income_category_id: cat.id})
      )
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )
      wages_usd = Accounting.get_account_by_code!("4000")
      credit_line = Enum.find(je.journal_lines, &(&1.credit_cents > 0))
      assert credit_line.account_id == wages_usd.id
    end

    test "resolves wages MXN revenue account for Wages & Salary category in MXN" do
      cat = income_category_fixture("Wages & Salary")
      {:ok, entry} = Income.create_income_entry_with_journal(
        income_attrs(%{currency: "MXN", income_category_id: cat.id})
      )
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )
      wages_mxn = Accounting.get_account_by_code!("4010")
      credit_line = Enum.find(je.journal_lines, &(&1.credit_cents > 0))
      assert credit_line.account_id == wages_mxn.id
    end

    test "falls back to other income account for unknown category" do
      cat = income_category_fixture("Random")
      {:ok, entry} = Income.create_income_entry_with_journal(
        income_attrs(%{income_category_id: cat.id})
      )
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )
      other_income = Accounting.get_account_by_code!("4050")
      credit_line = Enum.find(je.journal_lines, &(&1.credit_cents > 0))
      assert credit_line.account_id == other_income.id
    end

    test "falls back to other income account when no category" do
      {:ok, entry} = Income.create_income_entry_with_journal(income_attrs())
      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )
      other_income = Accounting.get_account_by_code!("4050")
      credit_line = Enum.find(je.journal_lines, &(&1.credit_cents > 0))
      assert credit_line.account_id == other_income.id
    end
  end

  # ── update_income_entry_with_journal/2 ─────────────────────────────────

  describe "update_income_entry_with_journal/2" do
    test "updates entry fields" do
      entry = income_fixture()
      assert {:ok, updated} = Income.update_income_entry_with_journal(entry, %{description: "Updated salary"})
      assert updated.description == "Updated salary"
    end

    test "updates amount and refreshes journal entry lines" do
      entry = income_fixture(%{amount_cents: 100_000})
      assert {:ok, updated} = Income.update_income_entry_with_journal(entry, %{amount_cents: 250_000})
      assert updated.amount_cents == 250_000

      reference = "Income ##{entry.id}"
      je = Repo.one(from j in Ledgr.Core.Accounting.JournalEntry,
        where: j.reference == ^reference,
        preload: :journal_lines
      )
      assert Enum.any?(je.journal_lines, &(&1.debit_cents == 250_000))
    end

    test "returns error changeset for invalid attrs" do
      entry = income_fixture()
      assert {:error, _} = Income.update_income_entry_with_journal(entry, %{amount_cents: -1})
    end
  end

  # ── delete_income_entry/1 ───────────────────────────────────────────────

  describe "delete_income_entry/1" do
    test "removes the entry record" do
      entry = income_fixture()
      {:ok, _} = Income.delete_income_entry(entry)
      assert_raise Ecto.NoResultsError, fn -> Income.get_income_entry!(entry.id) end
    end

    test "removes the entry from list_income_entries" do
      entry = income_fixture()
      {:ok, _} = Income.delete_income_entry(entry)
      refute Enum.any?(Income.list_income_entries(), &(&1.id == entry.id))
    end

    test "deletes the associated journal entry" do
      entry = income_fixture()
      reference = "Income ##{entry.id}"
      {:ok, _} = Income.delete_income_entry(entry)

      count = Repo.aggregate(
        from(j in Ledgr.Core.Accounting.JournalEntry, where: j.reference == ^reference),
        :count
      )
      assert count == 0
    end
  end

  # ── total_by_currency/2 ─────────────────────────────────────────────────

  describe "total_by_currency/2" do
    test "returns totals grouped by currency" do
      income_fixture(%{currency: "MXN", amount_cents: 200_000})
      income_fixture(%{currency: "MXN", amount_cents: 100_000})
      income_fixture(%{currency: "USD", amount_cents: 50_000, deposit_account_id: deposit_account().id})

      totals = Income.total_by_currency(~D[2026-01-01], ~D[2026-12-31])
      assert totals.mxn == 300_000
      assert totals.usd == 50_000
    end

    test "returns zeros when no entries in range" do
      income_fixture(%{date: ~D[2026-01-10]})
      totals = Income.total_by_currency(~D[2025-01-01], ~D[2025-12-31])
      assert totals.mxn == 0
      assert totals.usd == 0
    end

    test "correctly excludes entries outside date range" do
      income_fixture(%{date: ~D[2026-01-10], amount_cents: 100_000, currency: "MXN"})
      income_fixture(%{date: ~D[2026-06-10], amount_cents: 200_000, currency: "MXN"})

      totals = Income.total_by_currency(~D[2026-01-01], ~D[2026-01-31])
      assert totals.mxn == 100_000
    end
  end

  # ── totals_by_category_and_currency/2 ──────────────────────────────────

  describe "totals_by_category_and_currency/2" do
    test "returns rows with category and currency" do
      income_fixture(%{amount_cents: 150_000, currency: "MXN"})

      rows = Income.totals_by_category_and_currency(~D[2026-01-01], ~D[2026-12-31])
      assert length(rows) >= 1
      row = hd(rows)
      assert Map.has_key?(row, :currency)
      assert Map.has_key?(row, :total_cents)
    end

    test "returns empty list when no entries in range" do
      income_fixture(%{date: ~D[2026-01-10]})
      assert Income.totals_by_category_and_currency(~D[2025-01-01], ~D[2025-12-31]) == []
    end
  end
end
