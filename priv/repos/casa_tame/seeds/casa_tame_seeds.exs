alias Ledgr.Repo

# ── Chart of Accounts (dual currency) ──────────────────────────────

accounts = [
  # USD Assets
  %{code: "1000", name: "Cash (USD)", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1010", name: "Checking Account (USD)", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1020", name: "Savings Account (USD)", type: "asset", normal_balance: "debit", is_cash: true},

  # MXN Assets
  %{code: "1100", name: "Cash (MXN)", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1110", name: "Checking Account (MXN)", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1120", name: "Savings Account (MXN)", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1130", name: "Credit Card Payment Account (MXN)", type: "asset", normal_balance: "debit", is_cash: true},

  # Revenue
  %{code: "4000", name: "Wages & Salary (USD)", type: "revenue", normal_balance: "credit"},
  %{code: "4010", name: "Wages & Salary (MXN)", type: "revenue", normal_balance: "credit"},
  %{code: "4020", name: "Freelance Income", type: "revenue", normal_balance: "credit"},
  %{code: "4030", name: "Investment Returns", type: "revenue", normal_balance: "credit"},
  %{code: "4040", name: "Rental Income", type: "revenue", normal_balance: "credit"},
  %{code: "4050", name: "Other Income", type: "revenue", normal_balance: "credit"},

  # Expense accounts
  %{code: "6000", name: "Housing", type: "expense", normal_balance: "debit"},
  %{code: "6010", name: "Food & Dining", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Transportation", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Healthcare", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Entertainment", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Personal", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Financial Fees", type: "expense", normal_balance: "debit"},
  %{code: "6070", name: "Pets", type: "expense", normal_balance: "debit"},
  %{code: "6080", name: "Travel", type: "expense", normal_balance: "debit"},
  %{code: "6090", name: "Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6099", name: "Other Expenses", type: "expense", normal_balance: "debit"},
]

accounts
|> Enum.each(&SeedHelper.upsert_account/1)

IO.puts("Seeded #{length(accounts)} Casa Tame accounts")

# ── Expense Categories (hierarchical) ──────────────────────────────

alias Ledgr.Core.Accounting.Account
_ = Account  # suppress unused warning

# We'll insert directly since these are domain-specific tables
defmodule CasaTameSeedHelper do
  def upsert_expense_category(attrs, parent_id \\ nil) do
    import Ecto.Query
    alias Ledgr.Repo

    query =
      if parent_id do
        from(c in "expense_categories",
          where: c.name == ^attrs.name and c.parent_id == ^parent_id,
          select: c.id
        )
      else
        from(c in "expense_categories",
          where: c.name == ^attrs.name and is_nil(c.parent_id),
          select: c.id
        )
      end

    case Repo.one(query) do
      nil ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        {1, [%{id: id}]} =
          Repo.insert_all("expense_categories",
            [%{
              name: attrs.name,
              icon: attrs[:icon],
              parent_id: parent_id,
              is_system: true,
              inserted_at: now,
              updated_at: now
            }],
            returning: [:id]
          )

        id

      id ->
        id
    end
  end

  def upsert_income_category(attrs) do
    import Ecto.Query
    alias Ledgr.Repo

    query = from(c in "income_categories", where: c.name == ^attrs.name, select: c.id)

    case Repo.one(query) do
      nil ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        Repo.insert_all("income_categories",
          [%{
            name: attrs.name,
            icon: attrs[:icon],
            is_system: true,
            inserted_at: now,
            updated_at: now
          }]
        )

      _id ->
        :ok
    end
  end
end

# Parent categories with subcategories
categories = [
  {"Housing", nil, [
    "Rent/Mortgage", "Utilities", "Maintenance & Repairs", "Home Insurance",
    "Property Tax", "Furnishings"
  ]},
  {"Food & Dining", nil, [
    "Groceries", "Restaurants", "Delivery", "Coffee & Snacks"
  ]},
  {"Transportation", nil, [
    "Gas/Fuel", "Public Transit", "Parking & Tolls", "Car Maintenance",
    "Car Insurance", "Ride Sharing"
  ]},
  {"Healthcare", nil, [
    "Doctor & Specialist", "Pharmacy", "Health Insurance", "Dental", "Vision"
  ]},
  {"Entertainment", nil, [
    "Streaming Services", "Going Out", "Hobbies", "Books & Media", "Sports & Fitness"
  ]},
  {"Personal", nil, [
    "Clothing", "Grooming & Personal Care", "Education", "Gifts Given"
  ]},
  {"Financial", nil, [
    "Bank Fees", "Interest Payments", "Investment Fees", "Tax Payments", "Insurance Premiums"
  ]},
  {"Pets", nil, [
    "Pet Food", "Vet & Health", "Pet Supplies"
  ]},
  {"Travel", nil, [
    "Flights", "Hotels & Lodging", "Activities & Tours", "Travel Insurance"
  ]},
  {"Subscriptions", nil, [
    "Software & Apps", "Memberships", "Phone & Internet", "News & Magazines"
  ]},
  {"Other", nil, [
    "Donations", "Miscellaneous"
  ]}
]

category_count = Enum.reduce(categories, 0, fn {parent_name, _icon, children}, acc ->
  parent_id = CasaTameSeedHelper.upsert_expense_category(%{name: parent_name})

  Enum.each(children, fn child_name ->
    CasaTameSeedHelper.upsert_expense_category(%{name: child_name}, parent_id)
  end)

  acc + 1 + length(children)
end)

IO.puts("Seeded #{category_count} expense categories")

# ── Income Categories (flat) ───────────────────────────────────────

income_categories = [
  %{name: "Wages & Salary"},
  %{name: "Freelance"},
  %{name: "Investments & Dividends"},
  %{name: "Rental Income"},
  %{name: "Gifts Received"},
  %{name: "Tax Refund"},
  %{name: "Side Income"},
  %{name: "Other"}
]

Enum.each(income_categories, &CasaTameSeedHelper.upsert_income_category/1)

IO.puts("Seeded #{length(income_categories)} income categories")
