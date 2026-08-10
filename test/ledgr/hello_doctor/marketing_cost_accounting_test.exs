defmodule Ledgr.Domains.HelloDoctor.MarketingCostAccountingTest do
  @moduledoc """
  Pins the GL shape of a marketing cost, in both directions.

  Spend debits 6050 and credits 2310. A **credit** — a negative upload, i.e. a
  promo credit, refund or billing adjustment on the platform's invoice — posts
  the same entry with the sides swapped, because `JournalLine` rejects negative
  debit/credit cents: the sign has to live in which account takes which side.

  The deletion cases matter because a credit that deleted without reversing
  would leave the GL holding an entry with no row behind it.
  """
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.MarketingCostAccounting
  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  defp cost_fixture(attrs) do
    Repo.insert!(
      struct(
        %MarketingCost{
          platform: "google",
          date: ~D[2026-08-10],
          currency: "MXN",
          source: "csv",
          description: "Test charge"
        },
        attrs
      )
    )
  end

  # {debit_cents, credit_cents} on the given account code, for one entry.
  defp line_on(entry_id, code) do
    from(jl in Accounting.JournalLine,
      join: a in Accounting.Account,
      on: a.id == jl.account_id,
      where: jl.journal_entry_id == ^entry_id and a.code == ^code,
      select: {jl.debit_cents, jl.credit_cents}
    )
    |> Repo.one()
  end

  describe "post_to_gl/1 — spend" do
    test "debits 6050 and credits 2310" do
      cost = cost_fixture(%{amount: 28.43})

      assert {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)
      assert posted.spend_mxn_cents == 2843
      assert posted.posted_at

      assert line_on(posted.journal_entry_id, "6050") == {2843, 0}
      assert line_on(posted.journal_entry_id, "2310") == {0, 2843}
    end
  end

  describe "post_to_gl/1 — credit (negative amount)" do
    test "debits 2310 and credits 6050, with positive magnitudes" do
      cost = cost_fixture(%{amount: -2577.56, description: "Código promocional"})

      assert {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)

      # The sides are swapped; neither line carries a negative number.
      assert line_on(posted.journal_entry_id, "2310") == {257_756, 0}
      assert line_on(posted.journal_entry_id, "6050") == {0, 257_756}
    end

    test "stores spend_mxn_cents signed, so analytics SUMs net it against spend" do
      cost = cost_fixture(%{amount: -2577.56})

      assert {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)
      assert posted.spend_mxn_cents == -257_756
    end

    test "the entry describes itself as a credit, not as spend" do
      cost = cost_fixture(%{amount: -412.41})

      assert {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)
      entry = Repo.get!(Accounting.JournalEntry, posted.journal_entry_id)

      assert entry.description =~ "credit"
      refute entry.description =~ "spend"
    end

    test "a spend and an offsetting credit net to zero on 6050" do
      {:ok, spend} = cost_fixture(%{amount: 412.41}) |> MarketingCostAccounting.post_to_gl()
      {:ok, credit} = cost_fixture(%{amount: -412.41}) |> MarketingCostAccounting.post_to_gl()

      {d1, c1} = line_on(spend.journal_entry_id, "6050")
      {d2, c2} = line_on(credit.journal_entry_id, "6050")

      assert d1 + d2 - (c1 + c2) == 0
    end

    test "zero still refuses to post" do
      cost = cost_fixture(%{amount: 0.0})

      assert {:error, :zero_amount} = MarketingCostAccounting.post_to_gl(cost)
    end
  end

  describe "delete_cost/1" do
    test "reverses a posted credit instead of silently skipping it" do
      cost = cost_fixture(%{amount: -2577.56})
      {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)

      assert {:ok, _} = MarketingCostAccounting.delete_cost(posted)

      reversal =
        from(e in Accounting.JournalEntry,
          where: e.entry_type == "marketing_cost_reversal",
          order_by: [desc: e.id],
          limit: 1
        )
        |> Repo.one()

      assert reversal, "deleting a posted credit must leave a reversing entry"

      # Reversal is the mirror of the credit: back to Dr 6050 / Cr 2310.
      assert line_on(reversal.id, "6050") == {257_756, 0}
      assert line_on(reversal.id, "2310") == {0, 257_756}
    end

    test "reverses a posted spend the other way round" do
      cost = cost_fixture(%{amount: 28.43})
      {:ok, posted} = MarketingCostAccounting.post_to_gl(cost)

      assert {:ok, _} = MarketingCostAccounting.delete_cost(posted)

      reversal =
        from(e in Accounting.JournalEntry,
          where: e.entry_type == "marketing_cost_reversal",
          order_by: [desc: e.id],
          limit: 1
        )
        |> Repo.one()

      assert line_on(reversal.id, "2310") == {2843, 0}
      assert line_on(reversal.id, "6050") == {0, 2843}
    end
  end
end
