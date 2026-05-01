defmodule Ledgr.Core.Accounting.AccountTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.Account

  test "creates a valid account" do
    attrs = %{
      code: "1000",
      name: "Cash",
      type: "asset",
      normal_balance: "debit",
      is_cash: true
    }

    assert {:ok, %Account{} = account} = Accounting.create_account(attrs)
    assert account.code == "1000"
    assert account.type == "asset"
  end

  test "rejects invalid type" do
    attrs = %{
      code: "9999",
      name: "Weird",
      # invalid
      type: "weird",
      normal_balance: "debit",
      is_cash: false
    }

    assert {:error, changeset} = Accounting.create_account(attrs)
    assert "is invalid" in errors_on(changeset).type
  end

  test "enforces unique code" do
    valid = %{
      code: "2000",
      name: "Bank",
      type: "asset",
      normal_balance: "debit",
      is_cash: true
    }

    assert {:ok, _} = Accounting.create_account(valid)
    assert {:error, changeset} = Accounting.create_account(valid)
    assert "has already been taken" in errors_on(changeset).code
  end
end
