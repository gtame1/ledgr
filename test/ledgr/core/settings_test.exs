defmodule Ledgr.Core.SettingsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Settings
  alias Ledgr.Core.Settings.AppSetting

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)
    Ledgr.Domain.put_current(Ledgr.Domains.MrMunchMe)
    :ok
  end

  describe "get/1 and set/2" do
    test "get/1 returns nil for a missing key" do
      assert Settings.get("does_not_exist") == nil
    end

    test "set/2 inserts a new key and get/1 reads it back" do
      assert {:ok, %AppSetting{key: "feature_x", value: "on"}} = Settings.set("feature_x", "on")
      assert Settings.get("feature_x") == "on"
    end

    test "set/2 updates an existing key (upsert)" do
      {:ok, _} = Settings.set("theme", "light")
      assert Settings.get("theme") == "light"

      {:ok, updated} = Settings.set("theme", "dark")
      assert updated.value == "dark"
      assert Settings.get("theme") == "dark"
    end
  end

  describe "last_reconciled_date" do
    test "returns nil when unset" do
      assert Settings.get_last_reconciled_date() == nil
    end

    test "round-trips a Date" do
      date = ~D[2026-04-13]
      assert {:ok, _} = Settings.set_last_reconciled_date(date)
      assert Settings.get_last_reconciled_date() == date
    end

    test "overwrites a previous value" do
      {:ok, _} = Settings.set_last_reconciled_date(~D[2026-01-01])
      {:ok, _} = Settings.set_last_reconciled_date(~D[2026-02-15])
      assert Settings.get_last_reconciled_date() == ~D[2026-02-15]
    end
  end

  describe "last_inventory_reconciled_date" do
    test "returns nil when unset" do
      assert Settings.get_last_inventory_reconciled_date() == nil
    end

    test "round-trips a Date" do
      date = ~D[2026-03-20]
      assert {:ok, _} = Settings.set_last_inventory_reconciled_date(date)
      assert Settings.get_last_inventory_reconciled_date() == date
    end

    test "is independent from last_reconciled_date" do
      {:ok, _} = Settings.set_last_reconciled_date(~D[2026-04-01])
      {:ok, _} = Settings.set_last_inventory_reconciled_date(~D[2026-04-10])

      assert Settings.get_last_reconciled_date() == ~D[2026-04-01]
      assert Settings.get_last_inventory_reconciled_date() == ~D[2026-04-10]
    end
  end

  describe "AppSetting.changeset/2" do
    test "requires :key" do
      changeset = AppSetting.changeset(%AppSetting{}, %{value: "hello"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).key
    end

    test "accepts nil value" do
      changeset = AppSetting.changeset(%AppSetting{}, %{key: "anything"})
      assert changeset.valid?
    end

    test "enforces unique :key at the DB level" do
      {:ok, _} = Settings.set("dup_key", "a")

      {:error, changeset} =
        %AppSetting{}
        |> AppSetting.changeset(%{key: "dup_key", value: "b"})
        |> Ledgr.Repo.insert()

      assert "has already been taken" in errors_on(changeset).key
    end
  end
end
