defmodule Ledgr.Domains.HelloDoctor.DoctorPayoutImportTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.DoctorPayoutImport
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  defp uid(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp doctor_fixture(name \\ "Dr. Test") do
    Repo.insert!(%Doctor{
      id: uid("doc"),
      phone: uid("phone"),
      name: name,
      specialty: "Cardiology",
      is_available: true
    })
  end

  @header "doctor_id,amount,date,description\r\n"

  # Byte 0x92 is "í" in Mac Roman — what Excel-for-Mac's plain "CSV" export
  # writes for "Ginecología". It is not valid UTF-8 in any position.
  defp mac_roman_row(doctor_id),
    do: "#{doctor_id},100.00,2026-08-03,Pago Ginecolog" <> <<0x92>> <> "a\r\n"

  describe "parse/1 encoding" do
    test "rejects a non-UTF-8 file rather than letting bad bytes reach the DB" do
      doctor = doctor_fixture()
      ascii_row = "#{doctor.id},50.00,2026-08-02,Pago normal\r\n"

      assert {:error, %{rows: [], errors: [{line, msg}]}} =
               DoctorPayoutImport.parse(@header <> ascii_row <> mac_roman_row(doctor.id))

      # Header is line 1, so the Mac Roman row is line 3.
      assert line == 3
      assert msg =~ "not valid UTF-8"
      assert msg =~ "CSV UTF-8"
    end

    test "rejects the whole file — a clean row alongside a bad one is not imported" do
      doctor = doctor_fixture()
      ascii_row = "#{doctor.id},50.00,2026-08-02,Pago normal\r\n"

      assert {:error, %{rows: []}} =
               DoctorPayoutImport.parse(@header <> ascii_row <> mac_roman_row(doctor.id))
    end

    # Excel's "CSV UTF-8" export — the fix for the Mac Roman case above —
    # prepends these three bytes, which otherwise bind to the first header cell
    # and make validate_header/1 report doctor_id as missing.
    test "strips the UTF-8 BOM that Excel's \"CSV UTF-8\" export prepends" do
      doctor = doctor_fixture()
      csv = <<0xEF, 0xBB, 0xBF>> <> @header <> "#{doctor.id},75.50,2026-08-02,Pago\r\n"

      assert {:ok, %{rows: [row], errors: []}} = DoctorPayoutImport.parse(csv)
      assert row.doctor_id == doctor.id
      assert row.amount == 75.50
      assert row.date == ~D[2026-08-02]
    end

    test "accepts UTF-8 accented text unchanged" do
      doctor = doctor_fixture("Dra. Ramírez")
      csv = @header <> "#{doctor.id},120.00,2026-08-02,Pago Ginecología\r\n"

      assert {:ok, %{rows: [row], errors: []}} = DoctorPayoutImport.parse(csv)
      assert row.description == "Pago Ginecología"
      assert row.doctor_name == "Dra. Ramírez"
    end
  end
end
