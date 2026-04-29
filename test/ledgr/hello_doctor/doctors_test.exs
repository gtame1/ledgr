defmodule Ledgr.Domains.HelloDoctor.DoctorsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.Doctors
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  defp doctor_fixture(attrs \\ %{}) do
    attrs =
      %{
        "name" => "Dr. House #{System.unique_integer([:positive])}",
        "specialty" => "Cardiology",
        "phone" => "+521555#{System.unique_integer([:positive])}",
        "is_available" => true
      }
      |> Map.merge(Map.new(attrs, fn {k, v} -> {to_string(k), v} end))

    {:ok, doc} = Doctors.create_doctor(attrs)
    doc
  end

  describe "CRUD" do
    test "create_doctor/1 inserts with autogen id" do
      {:ok, d} =
        Doctors.create_doctor(%{
          "name" => "A",
          "specialty" => "X",
          "phone" => "555-1",
          "is_available" => true
        })

      assert is_binary(d.id)
      assert d.is_available
    end

    test "create_doctor/1 requires name, specialty, phone, is_available" do
      {:error, cs} = Doctors.create_doctor(%{})
      errs = errors_on(cs)
      assert "can't be blank" in errs.name
      assert "can't be blank" in errs.specialty
      assert "can't be blank" in errs.phone
    end

    test "create_doctor/1 enforces unique phone" do
      phone = "+52155599#{System.unique_integer([:positive])}"

      {:ok, _} =
        Doctors.create_doctor(%{
          "name" => "A",
          "specialty" => "X",
          "phone" => phone,
          "is_available" => true
        })

      {:error, cs} =
        Doctors.create_doctor(%{
          "name" => "B",
          "specialty" => "Y",
          "phone" => phone,
          "is_available" => true
        })

      assert "has already been taken" in errors_on(cs).phone
    end

    test "update_doctor/2 changes a field" do
      d = doctor_fixture()
      {:ok, updated} = Doctors.update_doctor(d, %{"specialty" => "Dermatology"})
      assert updated.specialty == "Dermatology"
    end

    test "delete_doctor/1 removes the row" do
      d = doctor_fixture()
      assert {:ok, _} = Doctors.delete_doctor(d)
      assert_raise Ecto.NoResultsError, fn -> Doctors.get_doctor!(d.id) end
    end

    test "change_doctor/2 returns a changeset" do
      assert %Ecto.Changeset{} = Doctors.change_doctor(%Doctor{}, %{})
    end

    test "get_doctor!/1 preloads consultations" do
      d = doctor_fixture()
      loaded = Doctors.get_doctor!(d.id)
      assert loaded.id == d.id
      assert is_list(loaded.consultations)
    end
  end

  describe "toggle_availability/1" do
    test "flips is_available" do
      d = doctor_fixture(%{"is_available" => true})
      {:ok, flipped} = Doctors.toggle_availability(d)
      refute flipped.is_available

      {:ok, flipped_again} = Doctors.toggle_availability(flipped)
      assert flipped_again.is_available
    end
  end

  describe "counts" do
    test "count_by_status/1 separates active vs inactive" do
      _a = doctor_fixture(%{"is_available" => true})
      _b = doctor_fixture(%{"is_available" => false})

      active = Doctors.count_by_status(:active)
      inactive = Doctors.count_by_status(:inactive)
      all = Doctors.count_by_status(:other)

      assert active >= 1
      assert inactive >= 1
      assert all >= active + inactive - 0
    end

    test "count_all/0 counts all rows" do
      _ = doctor_fixture()
      _ = doctor_fixture()
      assert Doctors.count_all() >= 2
    end
  end

  describe "list_doctors/1" do
    test "returns all by default, ordered by name" do
      _a = doctor_fixture(%{"name" => "Zeta #{System.unique_integer([:positive])}"})
      _b = doctor_fixture(%{"name" => "Alpha #{System.unique_integer([:positive])}"})

      names = Doctors.list_doctors() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end

    test "filters by status=active" do
      active = doctor_fixture(%{"is_available" => true})
      inactive = doctor_fixture(%{"is_available" => false})

      ids = Doctors.list_doctors(status: "active") |> Enum.map(& &1.id)
      assert active.id in ids
      refute inactive.id in ids
    end

    test "filters by status=inactive" do
      active = doctor_fixture(%{"is_available" => true})
      inactive = doctor_fixture(%{"is_available" => false})

      ids = Doctors.list_doctors(status: "inactive") |> Enum.map(& &1.id)
      refute active.id in ids
      assert inactive.id in ids
    end

    test "filters by specialty" do
      needle = "Neurology-#{System.unique_integer([:positive])}"
      matching = doctor_fixture(%{"specialty" => needle})
      _other = doctor_fixture(%{"specialty" => "Orthopedics"})

      ids = Doctors.list_doctors(specialty: needle) |> Enum.map(& &1.id)
      assert matching.id in ids
      assert length(ids) == 1
    end

    test "filters by search on name" do
      needle = "UniqueName-#{System.unique_integer([:positive])}"
      d = doctor_fixture(%{"name" => "Dr. #{needle}"})
      _other = doctor_fixture()

      ids = Doctors.list_doctors(search: needle) |> Enum.map(& &1.id)
      assert ids == [d.id]
    end

    test "empty/nil filters don't constrain" do
      d = doctor_fixture()
      ids = Doctors.list_doctors(status: "", specialty: "", search: "") |> Enum.map(& &1.id)
      assert d.id in ids
    end
  end

  describe "doctor_options/0 and specialty_options/0" do
    test "doctor_options/0 returns only available doctors" do
      available = doctor_fixture(%{"is_available" => true})
      unavailable = doctor_fixture(%{"is_available" => false})

      opts = Doctors.doctor_options()
      ids = Enum.map(opts, fn {_name, id} -> id end)

      assert available.id in ids
      refute unavailable.id in ids
    end

    test "specialty_options/0 returns {label, value} tuples from the specialties table" do
      # specialty_options/0 queries the specialties table (not doctors),
      # so we just assert the return shape is [{string, string}] or [].
      opts = Doctors.specialty_options()
      assert is_list(opts)
      assert Enum.all?(opts, fn {label, value} -> is_binary(label) and is_binary(value) end)
    end

    test "specialties/0 delegates to specialty_options/0" do
      _ = doctor_fixture()
      assert Doctors.specialties() == Doctors.specialty_options()
    end
  end

  describe "top_by_consultations/1" do
    test "returns up to limit, only available doctors" do
      _a = doctor_fixture(%{"is_available" => true})
      _b = doctor_fixture(%{"is_available" => true})
      _c = doctor_fixture(%{"is_available" => false})

      top2 = Doctors.top_by_consultations(2)
      assert length(top2) <= 2
      assert Enum.all?(top2, & &1.is_available)
    end
  end
end
