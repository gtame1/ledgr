# MrMunchMeAccountingApp

## Mix Tasks

### Diagnostic & Fix Tasks

#### Fix Withdrawal Accounts
Fixes historical withdrawal entries that incorrectly debited Owner's Equity (3000) instead of Owner's Drawings (3100).

```sh
MIX_ENV=prod mix fix_withdrawal_accounts           # Dry run - shows what would be fixed
MIX_ENV=prod mix fix_withdrawal_accounts --fix     # Apply the fix
```

#### Fix Gift Order Accounting
Fixes accounting entries for orders that were delivered as regular sales but later marked as gifts (`is_gift = true`). Reverses the original sale/COGS entries, records the gift expense (Dr Samples & Gifts 6070, Cr WIP 1220), and reclassifies any payments as gift contributions (Cr Other Income 4100) so AR and Customer Deposits stay clean.

```sh
MIX_ENV=prod mix fix_gift_order_accounting           # Dry run - shows what would be fixed
MIX_ENV=prod mix fix_gift_order_accounting --fix     # Apply the corrections
```

#### Diagnose COGS
Diagnoses and fixes duplicate COGS journal entries caused by pattern matching issues.

```sh
MIX_ENV=prod mix diagnose_cogs           # Dry run - shows duplicates
MIX_ENV=prod mix diagnose_cogs --fix     # Remove duplicates
```

#### Backfill Movement Costs
Backfills costs for inventory movements that have $0 cost (useful when movements were recorded before purchases).

```sh
MIX_ENV=prod mix backfill_movement_costs
```

#### Repair Inventory Quantities
Recalculates and repairs inventory quantities from movements.

```sh
MIX_ENV=prod mix repair_inventory_quantities
```

#### Verify Inventory Accounting
Runs comprehensive integrity checks on inventory accounting (WIP balance, COGS consistency, etc.).

```sh
MIX_ENV=prod mix verify_inventory_accounting
```

### Reset Tasks (⚠️ DESTRUCTIVE)

#### Reset Accounting Only
Deletes ALL journal entries and lines (accounting movements only). Keeps accounts, orders, and inventory.

```sh
MIX_ENV=prod mix reset_accounting_only
```

#### Reset Inventory Only
Deletes ALL inventory movements and stock levels. Keeps ingredients and locations.

```sh
MIX_ENV=prod mix reset_inventory_only
```

#### Reset All Tables
Deletes data from ALL main tables (accounts, orders, inventory, partners, etc.).

```sh
MIX_ENV=prod mix reset_all_tables
```

#### Reset and Seed
Clears ALL data and reruns the seeds file.

```sh
MIX_ENV=prod mix reset_and_seed
```

#### Seed New Tables
Runs priv/repo/seeds.exs without clearing data (useful for adding new seed data).

```sh
MIX_ENV=prod mix seed_new_tables
```

### Creating Users

Registration is disabled in the UI — accounts are created internally via the command line.

Use `--no-start` to avoid conflicting with a running web server:

```sh
mix run --no-start -e "
  Application.ensure_all_started(:bcrypt_elixir)
  Application.ensure_all_started(:ecto_sql)
  Ledgr.Repos.Viaxe.start_link([])
  Ledgr.Repo.put_active_repo(Ledgr.Repos.Viaxe)
  Ledgr.Core.Accounts.create_user(%{email: ~s(super@admin.com), password: ~s(Potato123)})
  |> IO.inspect()
"
```

For MrMunchMe, swap `Ledgr.Repos.Viaxe` with `Ledgr.Repos.MrMunchMe` in both lines.