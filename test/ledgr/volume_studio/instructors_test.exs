defmodule Ledgr.Domains.VolumeStudio.InstructorsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.VolumeStudio.Instructors
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor

  import Ledgr.Domains.VolumeStudio.Fixtures

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.VolumeStudio)
    :ok
  end

  describe "list_instructors/0" do
    test "returns all non-deleted instructors" do
      inst = instructor_fixture()
      instructors = Instructors.list_instructors()
      assert Enum.any?(instructors, fn i -> i.id == inst.id end)
    end

    test "excludes soft-deleted instructors" do
      inst = instructor_fixture()
      {:ok, _} = Instructors.delete_instructor(inst)

      instructors = Instructors.list_instructors()
      refute Enum.any?(instructors, fn i -> i.id == inst.id end)
    end

    test "returns instructors ordered by name" do
      instructor_fixture(%{name: "Zara"})
      instructor_fixture(%{name: "Anna"})

      instructors = Instructors.list_instructors()
      names = Enum.map(instructors, & &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "list_active_instructors/0" do
    test "returns only active instructors" do
      active = instructor_fixture(%{active: true})
      _inactive = instructor_fixture(%{active: false, name: "Inactive"})

      instructors = Instructors.list_active_instructors()
      assert Enum.any?(instructors, fn i -> i.id == active.id end)
      assert Enum.all?(instructors, fn i -> i.active == true end)
    end
  end

  describe "get_instructor!/1" do
    test "returns instructor with given id" do
      inst = instructor_fixture()
      found = Instructors.get_instructor!(inst.id)
      assert found.id == inst.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Instructors.get_instructor!(0)
      end
    end
  end

  describe "create_instructor/1" do
    test "creates an instructor with valid attrs" do
      attrs = %{name: "New Instructor", email: "new@example.com", active: true}
      assert {:ok, %Instructor{} = inst} = Instructors.create_instructor(attrs)
      assert inst.name == "New Instructor"
    end

    test "returns error with no name" do
      assert {:error, %Ecto.Changeset{}} = Instructors.create_instructor(%{})
    end

    test "returns error with invalid email format" do
      assert {:error, changeset} = Instructors.create_instructor(%{name: "Test", email: "not-an-email"})
      assert errors_on(changeset)[:email]
    end
  end

  describe "update_instructor/2" do
    test "updates an instructor's name" do
      inst = instructor_fixture(%{name: "Old Name"})
      assert {:ok, updated} = Instructors.update_instructor(inst, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "can deactivate an instructor" do
      inst = instructor_fixture(%{active: true})
      assert {:ok, updated} = Instructors.update_instructor(inst, %{active: false})
      assert updated.active == false
    end
  end

  describe "delete_instructor/1" do
    test "soft-deletes an instructor" do
      inst = instructor_fixture()
      assert {:ok, deleted} = Instructors.delete_instructor(inst)
      assert deleted.deleted_at != nil
    end
  end

  describe "change_instructor/2" do
    test "returns a changeset" do
      inst = instructor_fixture()
      assert %Ecto.Changeset{} = Instructors.change_instructor(inst, %{name: "Changed"})
    end
  end
end
