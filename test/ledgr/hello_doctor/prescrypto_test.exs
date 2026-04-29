defmodule Ledgr.Domains.HelloDoctor.PrescryptoTest do
  use Ledgr.DataCase, async: false

  alias Ledgr.Domains.HelloDoctor.Prescrypto
  alias Ledgr.Domains.HelloDoctor.Doctors
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  # ── Schema changeset ──────────────────────────────────────────────────────

  describe "Doctor changeset accepts Prescrypto fields" do
    test "accepts all five prescrypto fields" do
      attrs = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Dr. Test",
        "specialty" => "General",
        "phone" => "+521555#{System.unique_integer([:positive])}",
        "is_available" => true,
        "prescrypto_medic_id" => 42,
        "prescrypto_token" => "tok_abc",
        "prescrypto_specialty_no" => "ESP-001",
        "prescrypto_specialty_verified" => true,
        "prescrypto_synced_at" => DateTime.utc_now()
      }

      cs = Doctor.changeset(%Doctor{}, attrs)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :prescrypto_medic_id) == 42
      assert Ecto.Changeset.get_change(cs, :prescrypto_token) == "tok_abc"
      assert Ecto.Changeset.get_change(cs, :prescrypto_specialty_no) == "ESP-001"
      assert Ecto.Changeset.get_change(cs, :prescrypto_specialty_verified) == true
    end

    test "prescrypto fields are optional — changeset valid without them" do
      attrs = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Dr. Optional",
        "specialty" => "General",
        "phone" => "+521555#{System.unique_integer([:positive])}",
        "is_available" => true
      }

      cs = Doctor.changeset(%Doctor{}, attrs)
      assert cs.valid?
    end
  end

  # ── Prescrypto.create_medic/1 ─────────────────────────────────────────────

  describe "create_medic/1 — disabled" do
    test "returns {:error, :disabled} without making HTTP calls" do
      original = Application.get_env(:ledgr, :prescrypto)
      Application.put_env(:ledgr, :prescrypto, enabled: false)

      doctor = %Doctor{
        id: Ecto.UUID.generate(),
        name: "Dr. Test",
        email: "doc@test.com",
        cedula_profesional: "CED-001",
        specialty: "General",
        phone: "+521555",
        is_available: true,
        prescrypto_specialty_no: nil,
        university: nil
      }

      # No stub set up — if HTTP was called it would raise
      assert Prescrypto.create_medic(doctor) == {:error, :disabled}

      Application.put_env(:ledgr, :prescrypto, original)
    end
  end

  describe "create_medic/1 — missing fields" do
    test "returns {:error, :missing_email} when email is nil" do
      doctor = %Doctor{email: nil, cedula_profesional: "CED-001"}
      assert Prescrypto.create_medic(doctor) == {:error, :missing_email}
    end

    test "returns {:error, :missing_cedula} when cedula_profesional is nil" do
      doctor = %Doctor{email: "doc@test.com", cedula_profesional: nil}
      assert Prescrypto.create_medic(doctor) == {:error, :missing_cedula}
    end
  end

  describe "create_medic/1 — HTTP responses" do
    setup do
      original = Application.get_env(:ledgr, :prescrypto)

      Application.put_env(:ledgr, :prescrypto,
        enabled: true,
        base_url: "https://integration.prescrypto.com/",
        token: "test-token"
      )

      on_exit(fn -> Application.put_env(:ledgr, :prescrypto, original) end)
      :ok
    end

    test "201 response returns {:ok, %{prescrypto_medic_id: int, prescrypto_token: str}}" do
      Req.Test.stub(Ledgr.Domains.HelloDoctor.Prescrypto, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => 42, "token" => "tok_abc"}))
      end)

      doctor = %Doctor{
        id: Ecto.UUID.generate(),
        name: "Dr. Test",
        email: "doc@test.com",
        cedula_profesional: "CED-001",
        specialty: "General",
        phone: "+521555",
        is_available: true,
        prescrypto_specialty_no: "ESP-001",
        university: "UNAM"
      }

      assert {:ok, %{prescrypto_medic_id: 42, prescrypto_token: "tok_abc"}} =
               Prescrypto.create_medic(doctor)
    end

    test "400 response returns {:error, {:api_error, 400, body}}" do
      Req.Test.stub(Ledgr.Domains.HelloDoctor.Prescrypto, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"email" => ["This field is required."]}))
      end)

      doctor = %Doctor{
        id: Ecto.UUID.generate(),
        name: "Dr. Bad",
        email: "bad@test.com",
        cedula_profesional: "CED-BAD",
        specialty: "General",
        phone: "+521555",
        is_available: true,
        prescrypto_specialty_no: nil,
        university: nil
      }

      assert {:error, {:api_error, 400, %{"email" => ["This field is required."]}}} =
               Prescrypto.create_medic(doctor)
    end
  end

  # ── Doctors.create_doctor/1 integration ──────────────────────────────────

  describe "create_doctor/1 Prescrypto integration" do
    setup do
      original = Application.get_env(:ledgr, :prescrypto)

      Application.put_env(:ledgr, :prescrypto,
        enabled: true,
        base_url: "https://integration.prescrypto.com/",
        token: "test-token"
      )

      on_exit(fn -> Application.put_env(:ledgr, :prescrypto, original) end)
      :ok
    end

    test "success: Prescrypto 201 → doctor has prescrypto_medic_id and prescrypto_synced_at set" do
      Req.Test.stub(Ledgr.Domains.HelloDoctor.Prescrypto, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => 99, "token" => "tok_xyz"}))
      end)

      attrs = %{
        "name" => "Dr. Synced #{System.unique_integer([:positive])}",
        "specialty" => "Cardiology",
        "phone" => "+521555#{System.unique_integer([:positive])}",
        "is_available" => true,
        "email" => "synced#{System.unique_integer([:positive])}@test.com",
        "cedula_profesional" => "CED-#{System.unique_integer([:positive])}"
      }

      {:ok, doctor} = Doctors.create_doctor(attrs)
      assert doctor.prescrypto_medic_id == 99
      assert doctor.prescrypto_token == "tok_xyz"
      assert %DateTime{} = doctor.prescrypto_synced_at
    end

    test "failure: Prescrypto 400 → doctor still created, prescrypto_medic_id is nil, returns {:ok, doctor}" do
      Req.Test.stub(Ledgr.Domains.HelloDoctor.Prescrypto, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"email" => ["Invalid."]}))
      end)

      attrs = %{
        "name" => "Dr. Fail #{System.unique_integer([:positive])}",
        "specialty" => "Cardiology",
        "phone" => "+521555#{System.unique_integer([:positive])}",
        "is_available" => true,
        "email" => "fail#{System.unique_integer([:positive])}@test.com",
        "cedula_profesional" => "CED-#{System.unique_integer([:positive])}"
      }

      assert {:ok, doctor} = Doctors.create_doctor(attrs)
      assert is_binary(doctor.id)
      assert is_nil(doctor.prescrypto_medic_id)
      assert is_nil(doctor.prescrypto_synced_at)
    end
  end
end
