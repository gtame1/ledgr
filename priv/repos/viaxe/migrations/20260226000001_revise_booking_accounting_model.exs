defmodule Ledgr.Repos.Viaxe.Migrations.ReviseBookingAccountingModel do
  use Ecto.Migration

  def change do
    # ── Partners: add default_fee_rate ───────────────────────────────────────
    # Stored in basis points (e.g. 2000 = 20%). UI convenience default for
    # pre-filling partner_fee_rate on new bookings.
    alter table(:partners) do
      add :default_fee_rate, :integer, default: 0, null: false
    end

    # ── Bookings: agency commission fields ───────────────────────────────────
    # gross_commission_cents : full commission before partner deduction
    # partner_fee_cents      : Archer/Intermex cut (stored per-booking because
    #                          Intermex rate varies 65-90% per deal)
    # partner_fee_rate       : basis points used at creation (for audit/recalc)
    # partner_id             : which parent company (Archer / Intermex) handles this booking
    # commission_cents       : Viaxe's net = gross - partner_fee  (already existed)
    # total_cost_cents       : REMOVED — Viaxe is pure agency, no COGS
    alter table(:bookings) do
      add :gross_commission_cents, :integer, default: 0, null: false
      add :partner_fee_cents, :integer, default: 0, null: false
      add :partner_fee_rate, :integer, default: 0, null: false
      add :partner_id, references(:partners, on_delete: :nothing)
      remove :total_cost_cents, :integer, default: 0
    end

    create index(:bookings, [:partner_id])

    # ── BookingPayments: is_advance flag ─────────────────────────────────────
    # true  → payment received BEFORE booking completion (advance commission)
    #         DR Cash / CR Advance Commission (2200)
    # false → payment received AFTER booking completion (settles receivable)
    #         DR Cash / CR Commission Receivable (1100)
    alter table(:booking_payments) do
      add :is_advance, :boolean, default: false, null: false
    end
  end
end
