defmodule Ledgr.Repos.Viaxe.Migrations.CreateViaxeTables do
  use Ecto.Migration

  @moduledoc """
  Creates Viaxe domain-specific tables for the travel agency:
  suppliers, services, bookings, booking_items, booking_payments.
  """

  def change do
    # ── Suppliers (airlines, hotels, tour operators, etc.) ───
    create table(:suppliers) do
      add :name, :string, null: false
      add :contact_name, :string
      add :email, :string
      add :phone, :string
      add :category, :string  # airline, hotel, tour_operator, transfer, insurance
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:suppliers, [:category])

    # ── Services (service catalog) ───────────────────────────
    create table(:services) do
      add :name, :string, null: false
      add :category, :string, null: false  # flight, hotel, tour, transfer, insurance, package
      add :description, :text
      add :default_cost_cents, :integer
      add :default_price_cents, :integer
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:services, [:category])
    create index(:services, [:active])

    # ── Bookings ─────────────────────────────────────────────
    create table(:bookings) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "draft"
      add :booking_date, :date, null: false
      add :travel_date, :date
      add :return_date, :date
      add :passengers, :integer, default: 1
      add :destination, :string
      add :total_cost_cents, :integer, default: 0, null: false
      add :total_price_cents, :integer, default: 0, null: false
      add :commission_cents, :integer, default: 0, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:bookings, [:customer_id])
    create index(:bookings, [:status])
    create index(:bookings, [:booking_date])
    create index(:bookings, [:travel_date])

    create constraint(:bookings, :valid_booking_status,
      check: "status IN ('draft','confirmed','in_progress','completed','canceled')"
    )

    # ── Booking Items (line items within a booking) ──────────
    create table(:booking_items) do
      add :booking_id, references(:bookings, on_delete: :delete_all), null: false
      add :service_id, references(:services, on_delete: :restrict)
      add :supplier_id, references(:suppliers, on_delete: :restrict)
      add :description, :string, null: false
      add :cost_cents, :integer, null: false  # what we pay the supplier
      add :price_cents, :integer, null: false  # what we charge the customer
      add :quantity, :integer, default: 1, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:booking_items, [:booking_id])
    create index(:booking_items, [:service_id])
    create index(:booking_items, [:supplier_id])

    # ── Booking Payments ─────────────────────────────────────
    create table(:booking_payments) do
      add :booking_id, references(:bookings, on_delete: :restrict), null: false
      add :date, :date, null: false
      add :amount_cents, :integer, null: false
      add :payment_method, :string  # cash, transfer, card
      add :cash_account_id, references(:accounts, on_delete: :restrict)
      add :partner_id, references(:partners, on_delete: :restrict)
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:booking_payments, [:booking_id])
    create index(:booking_payments, [:date])
    create index(:booking_payments, [:partner_id])
  end
end
