defmodule Ledgr.Repos.VolumeStudio.Migrations.CreateVolumeStudioTables do
  use Ecto.Migration

  @moduledoc """
  Volume Studio domain-specific tables:
  - instructors
  - subscription_plans
  - subscriptions
  - class_sessions
  - class_bookings
  - consultations
  - spaces
  - space_rentals
  """

  def change do
    # ── Instructors ──────────────────────────────────────────
    create table(:instructors) do
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      add :specialty, :string        # e.g. yoga, pilates, nutrition
      add :bio, :text
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create index(:instructors, [:active])

    # ── Subscription Plans ───────────────────────────────────
    create table(:subscription_plans) do
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :duration_months, :integer, null: false, default: 1
      add :class_limit, :integer        # nil = unlimited
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    # ── Subscriptions (member enrollment) ───────────────────
    create table(:subscriptions) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :subscription_plan_id, references(:subscription_plans, on_delete: :restrict), null: false
      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :status, :string, null: false, default: "active"  # active | paused | cancelled | expired
      add :classes_used, :integer, default: 0, null: false
      add :deferred_revenue_cents, :integer, default: 0, null: false
      add :recognized_revenue_cents, :integer, default: 0, null: false
      add :notes, :text

      timestamps()
    end

    create index(:subscriptions, [:customer_id])
    create index(:subscriptions, [:subscription_plan_id])
    create index(:subscriptions, [:status])
    create index(:subscriptions, [:ends_on])

    create constraint(:subscriptions, :valid_status,
      check: "status IN ('active','paused','cancelled','expired')"
    )

    # ── Class Sessions ───────────────────────────────────────
    create table(:class_sessions) do
      add :instructor_id, references(:instructors, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :scheduled_at, :utc_datetime, null: false
      add :duration_minutes, :integer, null: false, default: 60
      add :capacity, :integer
      add :status, :string, null: false, default: "scheduled"  # scheduled | completed | cancelled
      add :notes, :text

      timestamps()
    end

    create index(:class_sessions, [:instructor_id])
    create index(:class_sessions, [:scheduled_at])
    create index(:class_sessions, [:status])

    create constraint(:class_sessions, :valid_status,
      check: "status IN ('scheduled','completed','cancelled')"
    )

    # ── Class Bookings ───────────────────────────────────────
    create table(:class_bookings) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :class_session_id, references(:class_sessions, on_delete: :restrict), null: false
      add :subscription_id, references(:subscriptions, on_delete: :nilify_all)  # nil = drop-in
      add :status, :string, null: false, default: "booked"  # booked | checked_in | no_show | cancelled
      add :paid_cents, :integer, default: 0, null: false    # for drop-in payments

      timestamps()
    end

    create index(:class_bookings, [:customer_id])
    create index(:class_bookings, [:class_session_id])
    create index(:class_bookings, [:subscription_id])
    create unique_index(:class_bookings, [:customer_id, :class_session_id])

    create constraint(:class_bookings, :valid_status,
      check: "status IN ('booked','checked_in','no_show','cancelled')"
    )

    # ── Consultations (diet / nutrition sessions) ────────────
    create table(:consultations) do
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :instructor_id, references(:instructors, on_delete: :restrict)
      add :scheduled_at, :utc_datetime, null: false
      add :duration_minutes, :integer, default: 60, null: false
      add :status, :string, null: false, default: "scheduled"  # scheduled | completed | cancelled | no_show
      add :notes, :text
      add :amount_cents, :integer, null: false
      add :iva_cents, :integer, default: 0, null: false
      add :paid_at, :date

      timestamps()
    end

    create index(:consultations, [:customer_id])
    create index(:consultations, [:instructor_id])
    create index(:consultations, [:scheduled_at])
    create index(:consultations, [:status])

    create constraint(:consultations, :valid_status,
      check: "status IN ('scheduled','completed','cancelled','no_show')"
    )

    # ── Spaces ───────────────────────────────────────────────
    create table(:spaces) do
      add :name, :string, null: false
      add :description, :text
      add :capacity, :integer
      add :hourly_rate_cents, :integer
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    # ── Space Rentals ────────────────────────────────────────
    create table(:space_rentals) do
      add :space_id, references(:spaces, on_delete: :restrict), null: false
      add :customer_id, references(:customers, on_delete: :nilify_all)  # optional link to customer record
      add :renter_name, :string, null: false
      add :renter_phone, :string
      add :renter_email, :string
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "confirmed"  # confirmed | active | completed | cancelled
      add :amount_cents, :integer, null: false
      add :iva_cents, :integer, default: 0, null: false
      add :paid_at, :date
      add :notes, :text

      timestamps()
    end

    create index(:space_rentals, [:space_id])
    create index(:space_rentals, [:customer_id])
    create index(:space_rentals, [:starts_at])
    create index(:space_rentals, [:status])

    create constraint(:space_rentals, :valid_status,
      check: "status IN ('confirmed','active','completed','cancelled')"
    )
  end
end
