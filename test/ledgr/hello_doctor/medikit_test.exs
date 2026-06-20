defmodule Ledgr.Domains.HelloDoctor.MedikitTest do
  use Ledgr.DataCase, async: false

  alias Ledgr.Domains.HelloDoctor.Medikit
  alias Ledgr.Domains.HelloDoctor.MedikitProvisioning
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  # base_url in enable_medikit/0 ends in "/api", so Req joins these full paths.
  @validate_path "/api/doctors/validate-professional-license"
  @register_path "/api/doctors"

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp enable_medikit do
    original = Application.get_env(:ledgr, :medikit)

    Application.put_env(:ledgr, :medikit,
      enabled: true,
      base_url: "https://uat.medikit.example/api",
      api_key: "test-api-key",
      payer: "0018c000029jpBgAAI",
      purchaser_plan: "0Sb8c000000TOYDCA4",
      country: "MX"
    )

    on_exit(fn -> Application.put_env(:ledgr, :medikit, original) end)
  end

  # All RAML-required fields populated → passes the completeness pre-flight.
  defp complete_attrs(extra) do
    %{
      "id" => Ecto.UUID.generate(),
      "name" => "Juan Perez Lopez",
      "specialty" => "General",
      "phone" => "+52155#{System.unique_integer([:positive])}",
      "is_available" => true,
      "first_name" => "Juan",
      "paternal_surname" => "Perez",
      "maternal_surname" => "Lopez",
      "cedula_profesional" => "12345678",
      "birthdate" => ~D[1980-01-01],
      "email" => "dr@test.com",
      "university" => "UANL",
      "medikit_specialty_id" => "0bc8c000000XcmfAAC",
      "address_state" => "NL",
      "address_city" => "Monterrey",
      "address_line" => "C. Washington 1400",
      "address_zipcode" => "64000"
    }
    |> Map.merge(extra)
  end

  defp insert_doctor(attrs) do
    %Doctor{}
    |> Doctor.changeset(complete_attrs(attrs))
    |> Ledgr.Repo.insert!()
  end

  defp complete_struct(extra) do
    struct(Doctor, %{
      id: "doc-1",
      first_name: "Gustavo",
      paternal_surname: "Pantera",
      maternal_surname: "Muniz",
      cedula_profesional: "01579846",
      birthdate: ~D[1975-09-20],
      phone: "525555555555",
      email: "dr@test.com",
      university: "UANL",
      medikit_specialty_id: "0bc8c000000XcmfAAC",
      address_state: "NL",
      address_city: "Monterrey",
      address_line: "C. Washington 1400",
      address_zipcode: "64000",
      gender: "Male",
      tax_id: "PAMG750920X00"
    })
    |> struct(extra)
  end

  # ── Schema changeset ──────────────────────────────────────────────────────

  describe "Doctor changeset — Medikit fields" do
    test "accepts the structured Medikit fields" do
      cs = Doctor.changeset(%Doctor{}, complete_attrs(%{}))
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :medikit_specialty_id) == "0bc8c000000XcmfAAC"
      assert Ecto.Changeset.get_change(cs, :birthdate) == ~D[1980-01-01]
    end

    test "rejects bad gender / state / zipcode formats" do
      cs =
        Doctor.changeset(
          %Doctor{},
          complete_attrs(%{"gender" => "X", "address_state" => "ZZ", "address_zipcode" => "abc"})
        )

      refute cs.valid?
      assert cs.errors[:gender]
      assert cs.errors[:address_state]
      assert cs.errors[:address_zipcode]
    end

    test "derives name from the structured name parts" do
      attrs = %{
        "id" => Ecto.UUID.generate(),
        "specialty" => "General",
        "phone" => "+52155#{System.unique_integer([:positive])}",
        "is_available" => true,
        "first_name" => "Ana",
        "paternal_surname" => "Gomez",
        "maternal_surname" => "Ruiz"
      }

      cs = Doctor.changeset(%Doctor{}, attrs)
      assert cs.valid?
      # name is required and not passed — it must come from the parts
      assert Ecto.Changeset.get_field(cs, :name) == "Ana Gomez Ruiz"
    end

    test "keeps existing name when editing a legacy doctor without name parts" do
      doctor = %Doctor{
        id: "d1",
        name: "Legacy Name",
        phone: "5550001111",
        specialty: "General",
        is_available: true
      }

      cs = Doctor.changeset(doctor, %{"email" => "x@y.com"})
      assert Ecto.Changeset.get_field(cs, :name) == "Legacy Name"
    end

    test "Medikit fields stay optional — a bare doctor still saves" do
      attrs = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Dr. Bare",
        "specialty" => "General",
        "phone" => "+52155#{System.unique_integer([:positive])}",
        "is_available" => true
      }

      assert Doctor.changeset(%Doctor{}, attrs).valid?
    end
  end

  # ── missing_register_fields/1 ─────────────────────────────────────────────

  describe "missing_register_fields/1" do
    test "empty for a complete doctor" do
      assert Medikit.missing_register_fields(complete_struct(%{})) == []
    end

    test "lists each blank required field" do
      missing = Medikit.missing_register_fields(complete_struct(%{birthdate: nil, address_city: ""}))
      assert :birthdate in missing
      assert :address_city in missing
      refute :email in missing
    end
  end

  # ── validate_professional_license/1 ───────────────────────────────────────

  describe "validate_professional_license/1" do
    test "{:error, :missing_cedula} when cedula absent (no HTTP)" do
      assert Medikit.validate_professional_license(%{cedula_profesional: nil}) ==
               {:error, :missing_cedula}
    end

    test "{:error, :disabled} when integration disabled" do
      original = Application.get_env(:ledgr, :medikit)
      Application.put_env(:ledgr, :medikit, enabled: false)
      on_exit(fn -> Application.put_env(:ledgr, :medikit, original) end)

      assert Medikit.validate_professional_license(complete_struct(%{})) == {:error, :disabled}
    end

    test "200 valid:true → {:ok, :valid}; sends the stored name parts + license" do
      enable_medikit()

      Req.Test.stub(Medikit, fn conn ->
        assert conn.request_path == @validate_path
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["professionalLicense"] == "01579846"
        assert decoded["firstName"] == "Gustavo"
        assert decoded["paternalLastName"] == "Pantera"
        assert decoded["maternalLastName"] == "Muniz"
        json(conn, 200, %{"valid" => true, "message" => "ok"})
      end)

      assert Medikit.validate_professional_license(complete_struct(%{})) == {:ok, :valid}
    end

    test "400 valid:false → {:ok, :invalid} (RAML returns 400 for bad license)" do
      enable_medikit()
      Req.Test.stub(Medikit, fn conn -> json(conn, 400, %{"valid" => false, "message" => "no"}) end)
      assert Medikit.validate_professional_license(complete_struct(%{})) == {:ok, :invalid}
    end

    test "500 → {:error, {:unexpected_status, 500}} (fail-closed)" do
      enable_medikit()
      Req.Test.stub(Medikit, fn conn -> json(conn, 500, %{"error" => "boom"}) end)
      assert {:error, {:unexpected_status, 500}} =
               Medikit.validate_professional_license(complete_struct(%{}))
    end
  end

  # ── register_doctor/1 ─────────────────────────────────────────────────────

  describe "register_doctor/1" do
    test "{:error, {:incomplete, missing}} when required fields blank (no HTTP)" do
      assert {:error, {:incomplete, missing}} =
               Medikit.register_doctor(complete_struct(%{birthdate: nil}))

      assert :birthdate in missing
    end

    test "200 Status:OK → {:ok, Data}; body carries identity, address, specialty" do
      enable_medikit()

      Req.Test.stub(Medikit, fn conn ->
        assert conn.request_path == @register_path
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        d = Jason.decode!(body)
        assert d["SourceSystemIdentifier"] == "doc-1"
        assert d["ProfessionalLicense"] == "01579846"
        assert d["Payer"] == "0018c000029jpBgAAI"
        assert d["SpecialtyId"] == "0bc8c000000XcmfAAC"
        assert d["LastName"] == "Pantera Muniz"
        assert d["Birthdate"] == "1975-09-20 00:00:00"
        assert d["Phone"] == "+525555555555"
        assert d["State"] == "NL"
        assert d["Country"] == "MX"
        json(conn, 200, %{"Status" => "OK", "Data" => "0cmE2000000BY9dIAG"})
      end)

      assert Medikit.register_doctor(complete_struct(%{})) == {:ok, "0cmE2000000BY9dIAG"}
    end

    test "200 Status:Error → {:error, {:rejected, ...}} (fail-closed)" do
      enable_medikit()

      Req.Test.stub(Medikit, fn conn ->
        json(conn, 200, %{"Status" => "Error", "Data" => "faltan parametros"})
      end)

      assert {:error, {:rejected, 200, _}} = Medikit.register_doctor(complete_struct(%{}))
    end
  end

  # ── doctor form component renders ─────────────────────────────────────────

  describe "DoctorHTML form components render" do
    import Phoenix.LiveViewTest

    test "name_fields renders the three structured name inputs" do
      cs = %Doctor{first_name: "Juan"} |> Doctor.changeset(%{})

      html =
        render_component(&LedgrWeb.Domains.HelloDoctor.DoctorHTML.name_fields/1, changeset: cs)

      assert html =~ ~s(name="doctor[first_name]")
      assert html =~ ~s(name="doctor[paternal_surname]")
      assert html =~ ~s(name="doctor[maternal_surname]")
      assert html =~ "value=\"Juan\""
    end

    test "medikit_fields renders the Medikit data inputs (no name parts)" do
      cs = Doctor.changeset(%Doctor{}, %{})

      html =
        render_component(&LedgrWeb.Domains.HelloDoctor.DoctorHTML.medikit_fields/1, changeset: cs)

      assert html =~ "Medikit"
      assert html =~ ~s(name="doctor[medikit_specialty_id]")
      assert html =~ ~s(name="doctor[address_state]")
      # name parts now live in name_fields, not here
      refute html =~ ~s(name="doctor[first_name]")
    end

    test "medikit_fields shows values + format errors after a submit" do
      cs =
        %Doctor{birthdate: ~D[1980-01-01]}
        |> Doctor.changeset(%{"address_zipcode" => "bad"})
        |> Map.put(:action, :update)

      html =
        render_component(&LedgrWeb.Domains.HelloDoctor.DoctorHTML.medikit_fields/1, changeset: cs)

      assert html =~ "1980-01-01"
      assert html =~ "must be 5–10 digits"
    end
  end

  # ── MedikitProvisioning.run/0 ─────────────────────────────────────────────

  describe "run/0 backfill" do
    setup do
      enable_medikit()
      :ok
    end

    test "complete + valid + registered candidate gets both columns set" do
      Req.Test.stub(Medikit, fn conn ->
        case conn.request_path do
          @validate_path -> json(conn, 200, %{"valid" => true})
          @register_path -> json(conn, 200, %{"Status" => "OK", "Data" => "HP-ABC"})
        end
      end)

      doctor = insert_doctor(%{"terms_accepted" => true})

      summary = MedikitProvisioning.run()
      assert summary.provisioned == 1

      reloaded = Ledgr.Repo.get!(Doctor, doctor.id)
      assert reloaded.medikit_healthcare_provider_id == "HP-ABC"
      assert %DateTime{} = reloaded.medikit_license_validated_at
    end

    test "incomplete candidate is skipped before any API call (fail-closed)" do
      # No HTTP stub: any API call would raise. Missing birthdate + address.
      doctor =
        insert_doctor(%{
          "terms_accepted" => true,
          "birthdate" => nil,
          "address_zipcode" => nil
        })

      summary = MedikitProvisioning.run()
      assert summary.incomplete == 1
      assert summary.provisioned == 0
      assert is_nil(Ledgr.Repo.get!(Doctor, doctor.id).medikit_healthcare_provider_id)
    end

    test "invalid license (400) leaves column NULL (fail-closed)" do
      Req.Test.stub(Medikit, fn conn -> json(conn, 400, %{"valid" => false}) end)

      doctor = insert_doctor(%{"terms_accepted" => true})

      summary = MedikitProvisioning.run()
      assert summary.invalid_license == 1
      assert is_nil(Ledgr.Repo.get!(Doctor, doctor.id).medikit_healthcare_provider_id)
    end

    test "register rejection leaves column NULL (fail-closed)" do
      Req.Test.stub(Medikit, fn conn ->
        case conn.request_path do
          @validate_path -> json(conn, 200, %{"valid" => true})
          @register_path -> json(conn, 200, %{"Status" => "Error", "Data" => "missing"})
        end
      end)

      doctor = insert_doctor(%{"terms_accepted" => true})

      summary = MedikitProvisioning.run()
      assert summary.failed == 1
      assert is_nil(Ledgr.Repo.get!(Doctor, doctor.id).medikit_healthcare_provider_id)
    end

    test "skips ineligible + already-provisioned doctors (idempotent)" do
      insert_doctor(%{"terms_accepted" => false})

      insert_doctor(%{
        "terms_accepted" => true,
        "deactivated_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      })

      insert_doctor(%{"terms_accepted" => true, "medikit_healthcare_provider_id" => "HP-EXISTING"})

      assert MedikitProvisioning.run().total == 0
    end
  end
end
