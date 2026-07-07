defmodule Ledgr.Repos.HelloDoctor.Migrations.AddMarketingPayableAccount do
  use Ecto.Migration

  @moduledoc """
  Credit side for marketing/ad spend, kept separate from the technology AP
  (2300) that external costs use. Debit side is the existing 6050 Marketing &
  Advertising expense account.
  """

  def up do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

    execute("""
      INSERT INTO accounts (code, name, type, normal_balance, is_cash, is_cogs, inserted_at, updated_at)
      VALUES ('2310', 'Accounts Payable - Marketing', 'liability', 'credit', false, false, '#{now}', '#{now}')
      ON CONFLICT (code) DO NOTHING
    """)
  end

  def down do
    # Don't delete — may have journal entries attached.
    :ok
  end
end
