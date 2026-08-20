# Production seeds for Viaxe
#
# Contains only real, stable business data required for the app to function:
# chart of accounts, suppliers, and service catalog.
#
# Intentionally excluded: customers, travel documents, trips, bookings,
# recommendations, and sample data — these are entered through the UI.
#
# Safe to run multiple times — all operations are idempotent (upsert by unique key).
# Run via: bin/ledgr eval "Ledgr.Release.seed()"

alias Ledgr.Repo
alias Ledgr.Core.Accounting.Account
alias Ledgr.Domains.Viaxe.Suppliers.Supplier
alias Ledgr.Domains.Viaxe.Services.Service
import Ecto.Query

# ── Core Accounts (shared across domains) ───────────────────

core_accounts = [
  %{code: "3000", name: "Owner's Equity",    type: "equity", normal_balance: "credit"},
  %{code: "3050", name: "Retained Earnings", type: "equity", normal_balance: "credit"},
  %{code: "3100", name: "Owner's Drawings",  type: "equity", normal_balance: "debit"},
]

for attrs <- core_accounts do
  case Repo.get_by(Account, code: attrs.code) do
    nil -> %Account{} |> Account.changeset(attrs) |> Repo.insert!()
    _existing -> :ok
  end
end

IO.puts("✅ Seeded #{length(core_accounts)} core accounts")

# ── Viaxe Chart of Accounts ──────────────────────────────────

viaxe_accounts = [
  # Assets
  %{code: "1000", name: "Cash",                 type: "asset",     normal_balance: "debit",  is_cash: true},
  %{code: "1010", name: "Bank Account",          type: "asset",     normal_balance: "debit",  is_cash: true},
  %{code: "1100", name: "Accounts Receivable",   type: "asset",     normal_balance: "debit"},
  # Liabilities
  %{code: "2100", name: "Supplier Payables",     type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Customer Deposits",     type: "liability", normal_balance: "credit"},
  # Revenue
  %{code: "4000", name: "Commission Revenue",    type: "revenue",   normal_balance: "credit"},
  %{code: "4100", name: "Service Fees",          type: "revenue",   normal_balance: "credit"},
  %{code: "4900", name: "Other Income",          type: "revenue",   normal_balance: "credit"},
  # COGS
  %{code: "5000", name: "Booking COGS",          type: "expense",   normal_balance: "debit",  is_cogs: true},
  # Operating Expenses
  %{code: "6000", name: "Office Rent",           type: "expense",   normal_balance: "debit"},
  %{code: "6010", name: "Utilities",             type: "expense",   normal_balance: "debit"},
  %{code: "6020", name: "Marketing & Advertising", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Travel & Entertainment", type: "expense",  normal_balance: "debit"},
  %{code: "6040", name: "Software & Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Insurance",             type: "expense",   normal_balance: "debit"},
  %{code: "6060", name: "Professional Services", type: "expense",   normal_balance: "debit"},
  %{code: "6070", name: "Office Supplies",       type: "expense",   normal_balance: "debit"},
  %{code: "6080", name: "Bank Fees",             type: "expense",   normal_balance: "debit"},
  %{code: "6090", name: "Miscellaneous Expenses", type: "expense",  normal_balance: "debit"},
]

for attrs <- viaxe_accounts do
  case Repo.get_by(Account, code: attrs.code) do
    nil -> %Account{} |> Account.changeset(attrs) |> Repo.insert!()
    _existing -> :ok
  end
end

IO.puts("✅ Seeded #{length(viaxe_accounts)} Viaxe accounts")

# ── Suppliers ────────────────────────────────────────────────

suppliers_data = [
  %{
    name: "Aeromexico",
    category: "airline",
    contact_name: "Reservations Desk",
    email: "reservations@aeromexico.com",
    phone: "+52-55-5133-4000",
    country: "Mexico",
    city: "Mexico City",
    website: "https://aeromexico.com"
  },
  %{
    name: "Barceló Hotels & Resorts",
    category: "hotel",
    contact_name: "Groups & Events",
    email: "groups@barcelo.com",
    phone: "+52-984-873-4444",
    country: "Mexico",
    city: "Cancún",
    website: "https://barcelo.com",
    address: "Blvd. Kukulcán Km 9.5, Zona Hotelera, Cancún"
  },
  %{
    name: "Hertz México",
    category: "transfer",
    contact_name: "Fleet Manager",
    email: "mexico@hertz.com",
    phone: "+52-800-709-5000",
    country: "Mexico",
    city: "Mexico City",
    website: "https://hertz.com.mx"
  },
  %{
    name: "Tulum Eco Tours",
    category: "tour_operator",
    contact_name: "Carlos Mendez",
    email: "hola@tulumecotours.mx",
    phone: "+52-984-115-8822",
    country: "Mexico",
    city: "Tulum",
    address: "Av. Tulum S/N, Centro, Tulum, Quintana Roo"
  },
]

for attrs <- suppliers_data do
  unless Repo.exists?(from s in Supplier, where: s.name == ^attrs.name) do
    %Supplier{} |> Supplier.changeset(attrs) |> Repo.insert!()
  end
end

IO.puts("✅ Seeded #{length(suppliers_data)} suppliers")

# ── Service Catalog ──────────────────────────────────────────

services_data = [
  %{name: "Economy Air Ticket",      category: "flight",    description: "Economy class airfare",                         price_cents: 1_200_000},
  %{name: "Business Air Ticket",     category: "flight",    description: "Business class airfare",                        price_cents: 4_500_000},
  %{name: "Hotel Night (Standard)",  category: "hotel",     description: "Standard double room per night",                price_cents: 250_000},
  %{name: "Hotel Night (Suite)",     category: "hotel",     description: "Junior suite per night",                        price_cents: 450_000},
  %{name: "Private Transfer",        category: "transfer",  description: "Airport-to-hotel private transfer",             price_cents: 120_000},
  %{name: "City Tour (Half Day)",    category: "tour",      description: "4-hour guided city tour",                       price_cents: 80_000},
  %{name: "Travel Insurance",        category: "insurance", description: "Comprehensive travel insurance per person/day", price_cents: 25_000},
]

for attrs <- services_data do
  unless Repo.exists?(from s in Service, where: s.name == ^attrs.name) do
    %Service{} |> Service.changeset(attrs) |> Repo.insert!()
  end
end

IO.puts("✅ Seeded #{length(services_data)} services")

# ── Admin User ───────────────────────────────────────────────

alias Ledgr.Core.Accounts

admin_email    = System.get_env("ADMIN_EMAIL")    || "admin@viaxe.com"
admin_password = System.get_env("ADMIN_PASSWORD") || raise "ADMIN_PASSWORD env var must be set in production"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, _} = Accounts.create_user(%{email: admin_email, password: admin_password})
    IO.puts("✅ Created Viaxe admin user: #{admin_email}")
  _existing ->
    IO.puts("ℹ️  Viaxe admin user already exists: #{admin_email}")
end
