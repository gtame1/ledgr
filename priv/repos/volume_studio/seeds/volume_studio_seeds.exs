# Reuses SeedHelper from core_seeds.exs (already loaded)

# ── Volume Studio Accounts ───────────────────────────────────────────────────

accounts = [
  # Assets
  %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit"},
  %{code: "1400", name: "IVA Receivable (Tax Credit)", type: "asset", normal_balance: "debit"},

  # Liabilities
  %{code: "2100", name: "IVA Payable", type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Deferred Subscription Revenue", type: "liability", normal_balance: "credit"},

  # Revenue
  %{code: "4000", name: "Subscription Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4010", name: "Class Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4020", name: "Consultation Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4030", name: "Space Rental Revenue", type: "revenue", normal_balance: "credit"},

  # Expenses
  %{code: "6010", name: "Instructor Fees", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Utilities (Gas, Electricity, Water)", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Advertising & Marketing", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Equipment & Supplies", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Cleaning & Maintenance", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Payment Processing Fees", type: "expense", normal_balance: "debit"},
  %{code: "6070", name: "Software & Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6080", name: "Permits & Licenses", type: "expense", normal_balance: "debit"},
  %{code: "6090", name: "Insurance", type: "expense", normal_balance: "debit"},
  %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit"},
]

accounts
|> Enum.each(&SeedHelper.upsert_account/1)

IO.puts("✅ Seeded #{length(accounts)} Volume Studio accounts")
