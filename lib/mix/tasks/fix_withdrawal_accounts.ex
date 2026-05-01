defmodule Mix.Tasks.FixWithdrawalAccounts do
  @moduledoc """
  Fixes historical withdrawal entries that incorrectly debited Owner's Equity (3000)
  instead of Owner's Drawings (3100).

  This task will:
  1. Find all withdrawal journal entries that debit Owner's Equity (3000)
  2. Create a correcting journal entry to transfer those debits to Owner's Drawings (3100)

  Usage:
    mix fix_withdrawal_accounts           # Dry run - shows what would be fixed
    mix fix_withdrawal_accounts --fix     # Actually applies the fix
  """

  use Mix.Task
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.{JournalLine, Account}

  @shortdoc "Fix historical withdrawal entries that debited Owner's Equity instead of Owner's Drawings"

  def run(args) do
    # Start only the Repo without the full application (avoids web server startup)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)

    # Build repo config from DATABASE_URL (prod) or app config (dev)
    repo_config =
      case System.get_env("DATABASE_URL") do
        nil ->
          # Dev: load app config first
          Application.load(:ledgr)
          Application.get_env(:ledgr, Ledgr.Repos.MrMunchMe) || []

        url ->
          # Prod: use DATABASE_URL with SSL for Render
          [
            url: url,
            pool_size: 2,
            ssl: true,
            ssl_opts: [verify: :verify_none]
          ]
      end

    {:ok, _} = Ledgr.Repos.MrMunchMe.start_link(repo_config)
    Ledgr.Repo.put_active_repo(Ledgr.Repos.MrMunchMe)

    fix_mode = "--fix" in args

    IO.puts("\n=== Fix Withdrawal Accounts ===\n")

    # Get account IDs
    owners_equity = get_account("3000")
    owners_drawings = get_account("3100")

    if is_nil(owners_equity) do
      IO.puts("❌ Owner's Equity account (3000) not found!")
      exit(:error)
    end

    if is_nil(owners_drawings) do
      IO.puts("❌ Owner's Drawings account (3100) not found!")
      IO.puts("   Run the migration first to create this account.")
      exit(:error)
    end

    # Find withdrawal entries that debit Owner's Equity
    incorrect_withdrawals = find_incorrect_withdrawals(owners_equity.id)

    if Enum.empty?(incorrect_withdrawals) do
      IO.puts("✅ No incorrect withdrawal entries found.")
      IO.puts("   All withdrawals are correctly debiting Owner's Drawings (3100).")
    else
      total_amount = Enum.reduce(incorrect_withdrawals, 0, fn w, acc -> acc + w.debit_cents end)

      IO.puts(
        "Found #{length(incorrect_withdrawals)} withdrawal line(s) incorrectly debiting Owner's Equity:"
      )

      IO.puts("")

      for w <- incorrect_withdrawals do
        IO.puts("  - Entry ##{w.journal_entry_id} (#{w.date}): #{w.reference}")
        IO.puts("    Amount: $#{format_cents(w.debit_cents)}")
      end

      IO.puts("")
      IO.puts("Total amount to correct: $#{format_cents(total_amount)}")
      IO.puts("")

      if fix_mode do
        IO.puts("Applying fix...")
        apply_fix(owners_equity, owners_drawings, total_amount)
      else
        IO.puts("This is a DRY RUN. To apply the fix, run:")
        IO.puts("  mix fix_withdrawal_accounts --fix")
      end
    end

    IO.puts("")
  end

  defp get_account(code) do
    Repo.get_by(Account, code: code)
  end

  defp find_incorrect_withdrawals(owners_equity_id) do
    from(jl in JournalLine,
      join: je in assoc(jl, :journal_entry),
      where:
        je.entry_type == "withdrawal" and
          jl.account_id == ^owners_equity_id and
          jl.debit_cents > 0,
      select: %{
        journal_entry_id: je.id,
        journal_line_id: jl.id,
        date: je.date,
        reference: je.reference,
        debit_cents: jl.debit_cents
      }
    )
    |> Repo.all()
  end

  defp apply_fix(owners_equity, owners_drawings, total_amount) do
    # Create a correcting journal entry
    # Dr. Owner's Equity (3000) - to reverse the incorrect debit (credit it)
    # Cr. Owner's Drawings (3100) - to apply the correct debit (debit it)
    #
    # Wait, that's backwards. Let me think...
    #
    # Original incorrect entry was: Dr. Owner's Equity (3000)
    # We want: Dr. Owner's Drawings (3100)
    #
    # Correction entry:
    # Dr. Owner's Drawings (3100) - to record the withdrawal correctly
    # Cr. Owner's Equity (3000) - to reverse the incorrect debit

    entry_attrs = %{
      date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
      entry_type: "other",
      reference: "Withdrawal Account Correction",
      description:
        "Correct historical withdrawals: move from Owner's Equity (3000) to Owner's Drawings (3100)"
    }

    lines = [
      %{
        account_id: owners_drawings.id,
        debit_cents: total_amount,
        credit_cents: 0,
        description: "Transfer historical withdrawals to Owner's Drawings"
      },
      %{
        account_id: owners_equity.id,
        debit_cents: 0,
        credit_cents: total_amount,
        description: "Reverse incorrect withdrawal debits from Owner's Equity"
      }
    ]

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, entry} ->
        IO.puts("✅ Correction entry created successfully!")
        IO.puts("   Journal Entry ID: #{entry.id}")
        IO.puts("")
        IO.puts("   Dr. Owner's Drawings (3100): $#{format_cents(total_amount)}")
        IO.puts("   Cr. Owner's Equity (3000):   $#{format_cents(total_amount)}")

      {:error, changeset} ->
        IO.puts("❌ Failed to create correction entry:")
        IO.inspect(changeset.errors)
    end
  end

  defp format_cents(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100, decimals: 2)
  end

  defp format_cents(cents) when is_struct(cents, Decimal) do
    cents |> Decimal.to_float() |> then(&:erlang.float_to_binary(&1, decimals: 2))
  end

  defp format_cents(_), do: "0.00"
end
