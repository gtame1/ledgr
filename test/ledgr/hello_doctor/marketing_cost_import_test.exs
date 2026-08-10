defmodule Ledgr.Domains.HelloDoctor.MarketingCostImportTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.MarketingCostImport

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  @header "date,platform,amount,currency,description\r\n"
  @ascii_row "2026-08-03,meta,805,MXN,27773016722382319-27745462128471113\r\n"

  # Byte 0x92 is "í" in Mac Roman — what Excel-for-Mac's plain "CSV" export
  # writes for "Ginecología". It is not valid UTF-8 in any position.
  @mac_roman_row "2026-08-04,google,44.75,MXN,Ginecolog" <> <<0x92>> <> "a - Search - MX\r\n"

  describe "parse/1 encoding" do
    test "rejects a non-UTF-8 file rather than letting bad bytes reach the DB" do
      assert {:error, %{rows: [], skipped: 0, errors: [{line, msg}]}} =
               MarketingCostImport.parse(@header <> @ascii_row <> @mac_roman_row)

      # Header is line 1, so the Mac Roman row is line 3.
      assert line == 3
      assert msg =~ "not valid UTF-8"
      assert msg =~ "CSV UTF-8"
    end

    test "rejects the whole file — a clean row alongside a bad one is not imported" do
      assert {:error, %{rows: []}} =
               MarketingCostImport.parse(@header <> @ascii_row <> @mac_roman_row)
    end

    # Excel's "CSV UTF-8" export — the fix for the Mac Roman case above —
    # prepends these three bytes, which otherwise bind to the first header cell.
    test "strips the UTF-8 BOM that Excel's \"CSV UTF-8\" export prepends" do
      csv = <<0xEF, 0xBB, 0xBF>> <> @header <> @ascii_row

      assert {:ok, %{rows: [row], errors: []}} = MarketingCostImport.parse(csv)
      assert row.platform == "meta"
      assert row.date == ~D[2026-08-03]
    end

    test "accepts UTF-8 accented text unchanged" do
      csv = @header <> "2026-08-04,google,44.75,MXN,Ginecología - Search - MX\r\n"

      assert {:ok, %{rows: [row], errors: []}} = MarketingCostImport.parse(csv)
      assert row.description == "Ginecología - Search - MX"
      assert row.platform == "google"
      assert row.amount == 44.75
    end
  end

  describe "parse/1 amounts" do
    test "accepts a negative amount — a promo credit on the platform invoice" do
      csv = @header <> "2026-08-10,google,-2577.56,MXN,Código promocional: 96TQH9T4PV3FH4\r\n"

      assert {:ok, %{rows: [row], errors: []}} = MarketingCostImport.parse(csv)
      assert row.amount == -2577.56
    end

    test "accepts a negative amount written with currency and thousands separators" do
      csv = @header <> "2026-08-10,google,\"-$2,577.56\",MXN,Promo credit\r\n"

      assert {:ok, %{rows: [row], errors: []}} = MarketingCostImport.parse(csv)
      assert row.amount == -2577.56
    end

    test "keeps positive spend and negative credits in the same file distinct" do
      csv =
        @header <>
          "2026-08-10,google,28.43,MXN,Servicio - Search - MX\r\n" <>
          "2026-08-10,google,-2577.56,MXN,Código promocional\r\n"

      assert {:ok, %{rows: [spend, credit], errors: []}} = MarketingCostImport.parse(csv)
      assert spend.amount == 28.43
      assert credit.amount == -2577.56
    end

    # Same magnitude, opposite sign — the dedup key includes `amount`, so a
    # credit must never be mistaken for the charge it offsets.
    test "a credit does not dedup against the equal-magnitude charge" do
      csv =
        @header <>
          "2026-08-10,google,412.41,MXN,Estimación\r\n" <>
          "2026-08-10,google,-412.41,MXN,Estimación\r\n"

      assert {:ok, %{rows: rows, skipped: 0, errors: []}} = MarketingCostImport.parse(csv)
      assert length(rows) == 2
    end

    test "still rejects an unparseable amount" do
      csv = @header <> "2026-08-10,google,not-a-number,MXN,Bad row\r\n"

      assert {:error, %{errors: [{2, msg}]}} = MarketingCostImport.parse(csv)
      assert msg =~ "invalid amount"
    end

    test "zero is accepted — the downloadable template ships 0.00 example rows" do
      csv = @header <> "2026-08-10,meta,0.00,MXN,Meta ad spend\r\n"

      assert {:ok, %{rows: [row], errors: []}} = MarketingCostImport.parse(csv)
      assert row.amount == 0.0
    end
  end
end
