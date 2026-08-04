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
end
