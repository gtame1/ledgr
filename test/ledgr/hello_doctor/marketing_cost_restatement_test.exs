defmodule Ledgr.Domains.HelloDoctor.MarketingCostRestatementTest do
  @moduledoc """
  A charge is identified by `{platform, date, description}`; `amount` is a
  mutable fact about it. These tests pin what happens when a re-upload carries
  a *different* amount for a charge already stored.

  This is the regression that motivated the design. `amount` used to be part of
  the identity, so every figure Google revised imported as a brand-new charge:
  "Servicio - Search - MX" on 2026-07-03 went 310.30 → 310.31 → 310.32 across
  three uploads and ended up in the ledger three times. Re-uploading Jun–Aug
  put $10,919 of phantom spend on the books, which had to be deleted by hand.
  """
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.HelloDoctor.MarketingCostAccounting
  alias Ledgr.Domains.HelloDoctor.MarketingCostImport
  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  @header "date,platform,amount,currency,description\r\n"

  defp upload(csv) do
    assert {:ok, parsed} = MarketingCostImport.parse(@header <> csv)
    {:ok, counts} = MarketingCostImport.commit(parsed)
    counts
  end

  defp stored(description) do
    Repo.get_by(MarketingCost, description: description)
  end

  # Net movement on an account across every entry, in cents.
  defp net_on(code) do
    from(jl in Accounting.JournalLine,
      join: a in Accounting.Account,
      on: a.id == jl.account_id,
      where: a.code == ^code,
      select: sum(jl.debit_cents) - sum(jl.credit_cents)
    )
    |> Repo.one() || 0
  end

  describe "a restated amount" do
    test "updates the existing row instead of inserting a second one" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      counts = upload("2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n")

      assert counts == %{inserted: 0, restated: 1}

      rows = Repo.all(from m in MarketingCost, where: m.description == "Servicio - Search - MX")
      assert length(rows) == 1, "a restatement must not create a second row"
      assert hd(rows).amount == 310.32
    end

    test "moves 6050 by the delta only, not by the whole restated amount" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      assert net_on("6050") == 31_030

      upload("2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n")

      # 310.32 total, NOT 310.30 + 310.32.
      assert net_on("6050") == 31_032
      assert net_on("2310") == -31_032
    end

    test "a downward restatement credits 6050 back" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      upload("2026-07-03,google,300.00,MXN,Servicio - Search - MX\r\n")

      assert net_on("6050") == 30_000
      assert stored("Servicio - Search - MX").amount == 300.00
    end

    test "records the adjustment as its own entry, leaving the original intact" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      original = stored("Servicio - Search - MX")

      upload("2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n")

      adjustment =
        Repo.one(
          from e in Accounting.JournalEntry,
            where: e.entry_type == "marketing_cost_adjustment"
        )

      assert adjustment, "the delta must be visible as its own journal entry"
      assert adjustment.date == ~D[2026-07-03], "adjustment belongs in the original's period"

      # The original entry is untouched — history isn't rewritten.
      assert Repo.get(Accounting.JournalEntry, original.journal_entry_id)
    end

    test "keeps spend_mxn_cents in step with the revised amount" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      upload("2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n")

      assert stored("Servicio - Search - MX").spend_mxn_cents == 31_032
    end

    test "the three-upload sequence that caused the incident leaves one row" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      upload("2026-07-03,google,310.31,MXN,Servicio - Search - MX\r\n")
      upload("2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n")

      rows = Repo.all(from m in MarketingCost, where: m.description == "Servicio - Search - MX")
      assert length(rows) == 1
      assert hd(rows).amount == 310.32
      assert net_on("6050") == 31_032
    end
  end

  describe "unchanged and new rows" do
    test "an identical re-upload changes nothing" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      before = net_on("6050")

      assert %{inserted: 0, restated: 0} =
               upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")

      assert net_on("6050") == before
    end

    test "a different campaign on the same day is a new charge, not a restatement" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")

      assert %{inserted: 1, restated: 0} =
               upload("2026-07-03,google,106.87,MXN,Ginecología - Search - MX\r\n")

      assert net_on("6050") == 31_030 + 10_687
    end

    test "the same campaign on a different day is a new charge" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")

      assert %{inserted: 1, restated: 0} =
               upload("2026-07-04,google,266.67,MXN,Servicio - Search - MX\r\n")
    end
  end

  describe "blank descriptions" do
    # Without a description the identity collapses to {platform, date}, which
    # legitimately holds several charges a day — so these can only be inserted
    # or skipped. This is precisely how the June duplicates arose.
    test "are never restated, only inserted or skipped" do
      upload("2026-06-10,google,149.88,MXN,\r\n")

      assert %{inserted: 1, restated: 0} = upload("2026-06-10,google,149.90,MXN,\r\n")

      rows = Repo.all(from m in MarketingCost, where: m.date == ^~D[2026-06-10])
      assert length(rows) == 2
    end

    test "an identical blank-description row is still skipped" do
      upload("2026-06-10,google,149.88,MXN,\r\n")
      assert %{inserted: 0, restated: 0} = upload("2026-06-10,google,149.88,MXN,\r\n")
    end
  end

  describe "ambiguity is refused, not guessed" do
    test "two amounts for one charge in a single file is an error" do
      csv =
        @header <>
          "2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n" <>
          "2026-07-03,google,310.32,MXN,Servicio - Search - MX\r\n"

      assert {:error, %{errors: [{3, msg}]}} = MarketingCostImport.parse(csv)
      assert msg =~ "one charge can only have one amount"
    end

    test "an exact duplicate line in a single file is an error" do
      csv =
        @header <>
          "2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n" <>
          "2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n"

      assert {:error, %{errors: [{3, msg}]}} = MarketingCostImport.parse(csv)
      assert msg =~ "duplicate of an earlier row"
    end

    test "refuses to restate when two stored rows share one identity" do
      # Pre-existing ambiguity, as the June/July data had before cleanup.
      for amount <- [310.30, 310.32] do
        Repo.insert!(%MarketingCost{
          platform: "google",
          date: ~D[2026-07-03],
          amount: amount,
          currency: "MXN",
          description: "Servicio - Search - MX",
          source: "csv"
        })
      end

      csv = @header <> "2026-07-03,google,310.35,MXN,Servicio - Search - MX\r\n"

      assert {:error, %{errors: [{2, msg}]}} = MarketingCostImport.parse(csv)
      assert msg =~ "2 existing charges share"
    end
  end

  describe "restate/2 directly" do
    test "is idempotent under a concurrent double-apply" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      cost = stored("Servicio - Search - MX")

      assert {:ok, %MarketingCost{}} = MarketingCostAccounting.restate(cost, 310.32)
      # Same stale struct again — as a racing request would hold.
      assert {:ok, :already_applied} = MarketingCostAccounting.restate(cost, 310.32)

      assert net_on("6050") == 31_032, "the delta must not be posted twice"
    end

    test "an unchanged amount is a no-op" do
      upload("2026-07-03,google,310.30,MXN,Servicio - Search - MX\r\n")
      cost = stored("Servicio - Search - MX")

      assert {:ok, :no_change} = MarketingCostAccounting.restate(cost, 310.30)
    end
  end
end
