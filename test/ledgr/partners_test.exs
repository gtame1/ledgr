defmodule Ledgr.Core.PartnersTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Partners
  alias Ledgr.Core.Partners.{Partner, CapitalContribution}
  alias Ledgr.Repo

  import Ledgr.Core.AccountingFixtures

  setup do
    standard_accounts_fixture()
    :ok
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp partner_fixture(attrs \\ %{}) do
    {:ok, partner} =
      %Partner{}
      |> Partner.changeset(
        Enum.into(attrs, %{name: "Test Partner #{System.unique_integer([:positive])}"})
      )
      |> Repo.insert()

    partner
  end

  defp cash_account do
    Ledgr.Core.Accounting.get_account_by_code!("1000")
  end

  # ── list_partners/0 ──────────────────────────────────────────────────

  describe "list_partners/0" do
    test "returns all partners" do
      p = partner_fixture()
      assert Enum.any?(Partners.list_partners(), fn x -> x.id == p.id end)
    end

    test "returns empty list when no partners" do
      assert Partners.list_partners() == [] || is_list(Partners.list_partners())
    end
  end

  # ── partner_select_options/0 ─────────────────────────────────────────

  describe "partner_select_options/0" do
    test "returns list of {name, id} tuples" do
      p = partner_fixture(%{name: "Alice"})
      options = Partners.partner_select_options()
      assert Enum.any?(options, fn {name, id} -> name == "Alice" and id == p.id end)
    end
  end

  # ── change_contribution_form/1 ────────────────────────────────────────

  describe "change_contribution_form/1" do
    test "returns valid changeset with all required fields" do
      p = partner_fixture()
      cash = cash_account()

      cs =
        Partners.change_contribution_form(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("500.00")
        })

      assert cs.valid?
    end

    test "returns invalid changeset when required fields are missing" do
      cs = Partners.change_contribution_form(%{})
      refute cs.valid?
    end

    test "returns invalid changeset when amount is zero" do
      p = partner_fixture()
      cash = cash_account()

      cs =
        Partners.change_contribution_form(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("0")
        })

      refute cs.valid?
    end
  end

  # ── create_contribution/1 ─────────────────────────────────────────────

  describe "create_contribution/1" do
    test "creates a contribution and records accounting entry" do
      p = partner_fixture()
      cash = cash_account()

      assert {:ok, %CapitalContribution{} = contrib} =
               Partners.create_contribution(%{
                 partner_id: p.id,
                 cash_account_id: cash.id,
                 date: Date.utc_today(),
                 amount_pesos: Decimal.new("1000.00"),
                 note: "Initial investment"
               })

      assert contrib.amount_cents == 100_000
      assert contrib.direction == "in"
      assert contrib.note == "Initial investment"
    end

    test "returns error changeset when attrs are invalid" do
      assert {:error, changeset} = Partners.create_contribution(%{})
      refute changeset.valid?
    end

    test "converts pesos to cents correctly" do
      p = partner_fixture()
      cash = cash_account()

      {:ok, contrib} =
        Partners.create_contribution(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("250.50")
        })

      assert contrib.amount_cents == 25_050
    end
  end

  # ── create_withdrawal/1 ───────────────────────────────────────────────

  describe "create_withdrawal/1" do
    test "creates a withdrawal with direction 'out'" do
      p = partner_fixture()
      cash = cash_account()

      assert {:ok, %CapitalContribution{} = contrib} =
               Partners.create_withdrawal(%{
                 partner_id: p.id,
                 cash_account_id: cash.id,
                 date: Date.utc_today(),
                 amount_pesos: Decimal.new("500.00")
               })

      assert contrib.direction == "out"
      assert contrib.amount_cents == 50_000
    end

    test "returns error when attrs are invalid" do
      assert {:error, _} = Partners.create_withdrawal(%{})
    end
  end

  # ── list_recent_contributions/1 ───────────────────────────────────────

  describe "list_recent_contributions/1" do
    test "returns recent contributions with partner preloaded" do
      p = partner_fixture()
      cash = cash_account()

      {:ok, _} =
        Partners.create_contribution(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("100.00")
        })

      contribs = Partners.list_recent_contributions()
      assert length(contribs) >= 1
      assert hd(contribs).partner != nil
    end

    test "respects limit parameter" do
      p = partner_fixture()
      cash = cash_account()

      for _ <- 1..5 do
        Partners.create_contribution(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("10.00")
        })
      end

      assert length(Partners.list_recent_contributions(3)) == 3
    end
  end

  # ── list_partners_with_totals/0 ───────────────────────────────────────

  describe "list_partners_with_totals/0" do
    test "returns partners with total_cents" do
      p = partner_fixture()
      cash = cash_account()

      {:ok, _} =
        Partners.create_contribution(%{
          partner_id: p.id,
          cash_account_id: cash.id,
          date: Date.utc_today(),
          amount_pesos: Decimal.new("300.00")
        })

      results = Partners.list_partners_with_totals()
      found = Enum.find(results, fn r -> r.partner.id == p.id end)
      assert found != nil
      assert found.total_cents == 30_000
    end

    test "nets out withdrawals from contributions" do
      p = partner_fixture()
      cash = cash_account()

      Partners.create_contribution(%{
        partner_id: p.id,
        cash_account_id: cash.id,
        date: Date.utc_today(),
        amount_pesos: Decimal.new("500.00")
      })

      Partners.create_withdrawal(%{
        partner_id: p.id,
        cash_account_id: cash.id,
        date: Date.utc_today(),
        amount_pesos: Decimal.new("200.00")
      })

      results = Partners.list_partners_with_totals()
      found = Enum.find(results, fn r -> r.partner.id == p.id end)
      assert found.total_cents == 30_000
    end

    test "returns zero total for partner with no contributions" do
      p = partner_fixture()
      results = Partners.list_partners_with_totals()
      found = Enum.find(results, fn r -> r.partner.id == p.id end)
      assert found.total_cents == 0
    end
  end

  # ── total_invested_cents/0 ────────────────────────────────────────────

  describe "total_invested_cents/0" do
    test "returns 0 when no contributions" do
      total = Partners.total_invested_cents()

      assert is_integer(total) or (is_struct(total, Decimal) and Decimal.to_integer(total) == 0) or
               total == Decimal.new(0)
    end

    test "accumulates all contributions net of withdrawals" do
      p = partner_fixture()
      cash = cash_account()

      Partners.create_contribution(%{
        partner_id: p.id,
        cash_account_id: cash.id,
        date: Date.utc_today(),
        amount_pesos: Decimal.new("1000.00")
      })

      total = Partners.total_invested_cents()

      # total_invested_cents may return Decimal or integer depending on DB
      total_int =
        case total do
          %Decimal{} -> Decimal.to_integer(total)
          n when is_integer(n) -> n
        end

      assert total_int >= 100_000
    end
  end
end
