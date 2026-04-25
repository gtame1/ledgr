defmodule Ledgr.Repos.HelloDoctor.Migrations.AddTechSubAccounts do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    new_accounts = [
      # Technology sub-accounts (children of 6040)
      %{code: "6041", name: "AI / OpenAI",                type: "expense",   normal_balance: "debit",  is_cash: false, is_cogs: false},
      %{code: "6042", name: "Video Calls / Whereby",      type: "expense",   normal_balance: "debit",  is_cash: false, is_cogs: false},
      %{code: "6043", name: "Cloud Hosting / AWS",        type: "expense",   normal_balance: "debit",  is_cash: false, is_cogs: false},
      # Liability account for technology credit card / AP
      %{code: "2300", name: "Accounts Payable - Technology", type: "liability", normal_balance: "credit", is_cash: false, is_cogs: false},
    ]

    for acct <- new_accounts do
      escaped_name = String.replace(acct.name, "'", "''")

      execute("""
        INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
        VALUES ('#{acct.code}', '#{escaped_name}', '#{acct.type}', '#{acct.normal_balance}', #{acct.is_cash}, #{acct.is_cogs}, '#{now}', '#{now}')
        ON CONFLICT (code) DO NOTHING
      """)
    end
  end

  def down do
    # Don't delete — may have journal entries attached
    :ok
  end
end
