defmodule Ledgr.Core.AccountsTest do
  use Ledgr.DataCase, async: true

  alias Ledgr.Core.Accounts
  alias Ledgr.Core.Accounts.User

  describe "create_user/1" do
    test "creates a user with valid email and password" do
      assert {:ok, %User{} = user} =
               Accounts.create_user(%{email: "test@example.com", password: "password123!"})

      assert user.email == "test@example.com"
      assert user.password_hash != nil
    end

    test "returns error with missing email" do
      assert {:error, changeset} = Accounts.create_user(%{password: "password123!"})
      assert errors_on(changeset)[:email]
    end

    test "returns error with short password" do
      assert {:error, changeset} = Accounts.create_user(%{email: "x@y.com", password: "short"})
      assert errors_on(changeset)[:password]
    end

    test "returns error with duplicate email" do
      Accounts.create_user(%{email: "dup@example.com", password: "password123!"})

      assert {:error, changeset} =
               Accounts.create_user(%{email: "dup@example.com", password: "password456!"})

      assert errors_on(changeset)[:email]
    end
  end

  describe "get_user_by_email/1" do
    test "returns user when found" do
      {:ok, user} = Accounts.create_user(%{email: "find@example.com", password: "password123!"})
      found = Accounts.get_user_by_email("find@example.com")
      assert found.id == user.id
    end

    test "returns nil when not found" do
      assert is_nil(Accounts.get_user_by_email("nobody@example.com"))
    end
  end

  describe "authenticate_by_email_and_password/2" do
    test "returns {:ok, user} with correct credentials" do
      {:ok, user} = Accounts.create_user(%{email: "auth@example.com", password: "password123!"})

      assert {:ok, found} =
               Accounts.authenticate_by_email_and_password("auth@example.com", "password123!")

      assert found.id == user.id
    end

    test "returns error with wrong password" do
      Accounts.create_user(%{email: "auth2@example.com", password: "password123!"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_email_and_password("auth2@example.com", "wrong")
    end

    test "returns error when user does not exist" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_email_and_password("ghost@example.com", "password123!")
    end
  end

  describe "change_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = Accounts.change_registration(%User{})
    end

    test "returns changeset with given attrs" do
      cs = Accounts.change_registration(%User{}, %{email: "new@example.com"})
      assert cs.changes[:email] == "new@example.com"
    end
  end
end
