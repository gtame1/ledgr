alias Ledgr.Repo
alias Ledgr.Core.Accounting.Account
alias Ledgr.Domains.Viaxe.Customers.{Customer, CustomerTravelProfile}
alias Ledgr.Domains.Viaxe.TravelDocuments.{Passport, Visa, LoyaltyProgram}
alias Ledgr.Domains.Viaxe.Suppliers.Supplier
alias Ledgr.Domains.Viaxe.Services.Service
alias Ledgr.Domains.Viaxe.Trips.{Trip, TripPassenger}
alias Ledgr.Domains.Viaxe.Bookings.{Booking, BookingItem}
alias Ledgr.Domains.Viaxe.Recommendations.Recommendation
import Ecto.Query

# ── Viaxe Chart of Accounts ──────────────────────────────────

viaxe_accounts = [
  # Assets
  %{code: "1000", name: "Cash", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1010", name: "Bank Account", type: "asset", normal_balance: "debit", is_cash: true},
  %{code: "1100", name: "Accounts Receivable", type: "asset", normal_balance: "debit"},

  # Liabilities
  %{code: "2100", name: "Supplier Payables", type: "liability", normal_balance: "credit"},
  %{code: "2200", name: "Customer Deposits", type: "liability", normal_balance: "credit"},

  # Revenue
  %{code: "4000", name: "Commission Revenue", type: "revenue", normal_balance: "credit"},
  %{code: "4100", name: "Service Fees", type: "revenue", normal_balance: "credit"},

  # Cost of Goods Sold
  %{code: "5000", name: "Booking COGS", type: "expense", normal_balance: "debit", is_cogs: true},

  # Operating Expenses
  %{code: "6000", name: "Office Rent", type: "expense", normal_balance: "debit"},
  %{code: "6010", name: "Utilities", type: "expense", normal_balance: "debit"},
  %{code: "6020", name: "Marketing & Advertising", type: "expense", normal_balance: "debit"},
  %{code: "6030", name: "Travel & Entertainment", type: "expense", normal_balance: "debit"},
  %{code: "6040", name: "Software & Subscriptions", type: "expense", normal_balance: "debit"},
  %{code: "6050", name: "Insurance", type: "expense", normal_balance: "debit"},
  %{code: "6060", name: "Professional Services", type: "expense", normal_balance: "debit"},
  %{code: "6070", name: "Office Supplies", type: "expense", normal_balance: "debit"},
  %{code: "6080", name: "Bank Fees", type: "expense", normal_balance: "debit"},
  %{code: "6090", name: "Miscellaneous Expenses", type: "expense", normal_balance: "debit"},

  # Other Income
  %{code: "4900", name: "Other Income", type: "revenue", normal_balance: "credit"},
]

for attrs <- viaxe_accounts do
  case Repo.get_by(Account, code: attrs.code) do
    nil ->
      %Account{}
      |> Account.changeset(attrs)
      |> Repo.insert!()

    _existing ->
      :ok
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

# ── Services ────────────────────────────────────────────────

services_data = [
  %{name: "Economy Air Ticket",  category: "flight",    description: "Economy class airfare", price_cents: 1_200_000},
  %{name: "Business Air Ticket", category: "flight",    description: "Business class airfare", price_cents: 4_500_000},
  %{name: "Hotel Night (Standard)", category: "hotel",  description: "Standard double room per night", price_cents: 250_000},
  %{name: "Hotel Night (Suite)",    category: "hotel",  description: "Junior suite per night", price_cents: 450_000},
  %{name: "Private Transfer",    category: "transfer",  description: "Airport-to-hotel private transfer", price_cents: 120_000},
  %{name: "City Tour (Half Day)", category: "tour",     description: "4-hour guided city tour", price_cents: 80_000},
  %{name: "Travel Insurance",    category: "insurance", description: "Comprehensive travel insurance per person/day", price_cents: 25_000},
]

for attrs <- services_data do
  unless Repo.exists?(from s in Service, where: s.name == ^attrs.name) do
    %Service{} |> Service.changeset(attrs) |> Repo.insert!()
  end
end

IO.puts("✅ Seeded #{length(services_data)} services")

# ── Customers ───────────────────────────────────────────────

customers_seed = [
  %{
    first_name: "Ana",
    last_name: "García",
    maternal_last_name: "López",
    email: "ana.garcia@email.com",
    phone: "+52-55-1234-5678",
    travel_profile: %{
      dob: ~D[1985-06-15],
      gender: "female",
      nationality: "Mexican",
      seat_preference: "window",
      meal_preference: "vegetarian",
      emergency_contact_name: "Roberto García",
      emergency_contact_phone: "+52-55-9876-5432"
    }
  },
  %{
    first_name: "Miguel",
    last_name: "Hernández",
    maternal_last_name: "Ruiz",
    email: "miguel.hdz@email.com",
    phone: "+52-55-2345-6789",
    travel_profile: %{
      dob: ~D[1978-03-22],
      gender: "male",
      nationality: "Mexican",
      seat_preference: "aisle",
      meal_preference: "regular"
    }
  },
  %{
    first_name: "Sofia",
    last_name: "Martínez",
    email: "sofia.m@email.com",
    phone: "+52-55-3456-7890",
    travel_profile: %{
      dob: ~D[1992-11-08],
      gender: "female",
      nationality: "Mexican",
      tsa_precheck_number: "AB12345678",
      seat_preference: "window",
      meal_preference: "gluten_free",
      medical_notes: "Celiac disease — strictly gluten free"
    }
  },
  %{
    first_name: "Carlos",
    last_name: "Ramírez",
    email: "carlos.ramirez@corp.com",
    phone: "+52-55-4567-8901",
    travel_profile: %{
      dob: ~D[1980-09-30],
      gender: "male",
      nationality: "Mexican",
      seat_preference: "aisle",
      meal_preference: "regular",
      emergency_contact_name: "Laura Ramírez",
      emergency_contact_phone: "+52-55-8765-4321"
    }
  },
]

created_customers = for attrs <- customers_seed do
  profile_attrs = Map.get(attrs, :travel_profile, %{})
  customer_attrs = Map.delete(attrs, :travel_profile)

  customer =
    case Repo.get_by(Customer, phone: customer_attrs.phone) do
      nil ->
        %Customer{} |> Customer.changeset(customer_attrs) |> Repo.insert!()
      existing ->
        existing
    end

  unless Repo.get_by(CustomerTravelProfile, customer_id: customer.id) do
    %CustomerTravelProfile{}
    |> CustomerTravelProfile.changeset(Map.put(profile_attrs, :customer_id, customer.id))
    |> Repo.insert!()
  end

  customer
end

IO.puts("✅ Seeded #{length(created_customers)} customers with travel profiles")

# ── Sample Passports & Loyalty Programs ─────────────────────

[ana, miguel | _] = created_customers

unless Repo.exists?(from p in Passport, where: p.customer_id == ^ana.id) do
  %Passport{}
  |> Passport.changeset(%{
    customer_id: ana.id,
    country: "Mexico",
    number: "G12345678",
    issue_date: ~D[2020-01-10],
    expiry_date: ~D[2030-01-09],
    is_primary: true
  })
  |> Repo.insert!()
end

unless Repo.exists?(from p in Passport, where: p.customer_id == ^miguel.id) do
  %Passport{}
  |> Passport.changeset(%{
    customer_id: miguel.id,
    country: "Mexico",
    number: "H87654321",
    issue_date: ~D[2019-05-20],
    expiry_date: ~D[2029-05-19],
    is_primary: true
  })
  |> Repo.insert!()
end

unless Repo.exists?(from lp in LoyaltyProgram, where: lp.customer_id == ^miguel.id) do
  %LoyaltyProgram{}
  |> LoyaltyProgram.changeset(%{
    customer_id: miguel.id,
    program_name: "AAdvantage",
    program_type: "airline",
    member_number: "AA1234567",
    tier: "Gold"
  })
  |> Repo.insert!()
end

IO.puts("✅ Seeded sample travel documents")

# ── Recommendations ──────────────────────────────────────────

recommendations_data = [
  %{city: "Cancún", country: "Mexico", category: "restaurant", name: "La Destilería",
    description: "Authentic Mexican cuisine with a wide tequila selection. Great for group dinners.",
    price_range: "$$", rating: 4},
  %{city: "Cancún", country: "Mexico", category: "beach", name: "Playa Delfines",
    description: "Public beach with stunning turquoise water and no resort crowds. Free entry.",
    price_range: "$", rating: 5},
  %{city: "Cancún", country: "Mexico", category: "experience", name: "Xcaret Park",
    description: "Cultural and natural theme park — snorkeling, river caves, evening show.",
    price_range: "$$$", rating: 5, website: "https://xcaret.com"},
  %{city: "Tulum", country: "Mexico", category: "hotel", name: "Azulik Tulum",
    description: "Eco-chic treehouse-style bungalows. Adults only. Stunning jungle-meets-sea setting.",
    price_range: "$$$$", rating: 5, website: "https://azulik.com"},
  %{city: "Tulum", country: "Mexico", category: "restaurant", name: "Hartwood",
    description: "Open-air kitchen serving wood-fired local ingredients. Reserve well in advance.",
    price_range: "$$$", rating: 5},
  %{city: "Tulum", country: "Mexico", category: "tour", name: "Cobá Ruins & Cenote Tour",
    description: "Full-day tour to Cobá pyramid and nearby cenotes. Guided, with lunch.",
    price_range: "$$", rating: 4},
  %{city: "Mexico City", country: "Mexico", category: "museum", name: "Museo Nacional de Antropología",
    description: "World-class museum covering pre-Columbian Mexican civilizations. Allow 3+ hours.",
    price_range: "$", rating: 5},
  %{city: "Mexico City", country: "Mexico", category: "restaurant", name: "Pujol",
    description: "Award-winning contemporary Mexican cuisine by Chef Enrique Olvera.",
    price_range: "$$$$", rating: 5, website: "https://pujol.com.mx"},
  %{city: "Mexico City", country: "Mexico", category: "experience", name: "Lucha Libre at Arena México",
    description: "The classic Mexican wrestling experience. Friday nights are best for atmosphere.",
    price_range: "$", rating: 4},
  %{city: "Oaxaca", country: "Mexico", category: "tour", name: "Mezcal Distillery Tour",
    description: "Visit a traditional palenque in the Valles Centrales. Includes tasting and lunch.",
    price_range: "$$", rating: 5},
  %{city: "Oaxaca", country: "Mexico", category: "restaurant", name: "Casa Oaxaca",
    description: "Rooftop restaurant with stunning views and classic Oaxacan mole.",
    price_range: "$$$", rating: 4},
]

for attrs <- recommendations_data do
  unless Repo.exists?(from r in Recommendation, where: r.name == ^attrs.name and r.city == ^attrs.city) do
    %Recommendation{} |> Recommendation.changeset(attrs) |> Repo.insert!()
  end
end

IO.puts("✅ Seeded #{length(recommendations_data)} recommendations")

# ── Sample Trip ──────────────────────────────────────────────

trip =
  case Repo.get_by(Trip, title: "Cancún Honeymoon 2026") do
    nil ->
      %Trip{}
      |> Trip.changeset(%{
        title: "Cancún Honeymoon 2026",
        description: "5-night romantic getaway to Cancún for the García family.",
        start_date: ~D[2026-04-10],
        end_date: ~D[2026-04-15],
        status: "confirmed"
      })
      |> Repo.insert!()
    existing -> existing
  end

[ana, miguel | _] = created_customers

for customer_id <- [ana.id, miguel.id] do
  unless Repo.exists?(from tp in TripPassenger,
    where: tp.trip_id == ^trip.id and tp.customer_id == ^customer_id) do
    %TripPassenger{}
    |> TripPassenger.changeset(%{
      trip_id: trip.id,
      customer_id: customer_id,
      is_primary_contact: customer_id == ana.id
    })
    |> Repo.insert!()
  end
end

# Sample flight booking for the trip
unless Repo.exists?(from b in Booking, where: b.trip_id == ^trip.id and b.booking_type == "flight") do
  {:ok, booking} =
    %Booking{}
    |> Booking.changeset(%{
      customer_id: ana.id,
      trip_id: trip.id,
      booking_type: "flight",
      booking_date: ~D[2026-02-01],
      travel_date: ~D[2026-04-10],
      return_date: ~D[2026-04-15],
      destination: "Cancún, Mexico",
      commission_type: "percentage",
      commission_value: 1000,  # 10.00%
      status: "confirmed",
      notes: "Direct flight MEX-CUN. Seats 12A and 12B."
    })
    |> Repo.insert()

  %BookingItem{}
  |> BookingItem.changeset(%{
    booking_id: booking.id,
    description: "MEX → CUN (Economy, 2 pax)",
    quantity: 2,
    cost_cents: 1_100_000,
    price_cents: 1_200_000
  })
  |> Repo.insert!()
end

IO.puts("✅ Seeded sample trip: #{trip.title}")
