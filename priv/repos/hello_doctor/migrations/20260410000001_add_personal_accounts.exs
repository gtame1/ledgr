defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPersonalAccounts do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    for {code, name, type, normal_balance, is_cash} <- [
      {"1300", "Eduvision Bank Account", "asset", "debit", true},
      {"1400", "Guillo Personal Bank Account", "asset", "debit", true},
      {"2300", "Eduvision CC", "liability", "credit", false},
      {"2400", "Guillo Personal Credit Card", "liability", "credit", false}
    ] do
      execute("""
        INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
        VALUES ('#{code}', '#{name}', '#{type}', '#{normal_balance}', #{is_cash}, false, '#{now}', '#{now}')
        ON CONFLICT (code) DO NOTHING
      """)
    end
  end

  def down, do: :ok
end
