defmodule Ledgr.Repos.HelloDoctor.Migrations.AddRetentionsToDoctorPayouts do
  use Ecto.Migration

  # Per-payout tax withholdings (ISR / IVA retenciones) held back from the
  # doctor and owed to SAT. Bookkept against the 2200 Taxes Payable account
  # by `DoctorPayouts.create_payout/1` and `update_payout/2`.
  def change do
    alter table(:doctor_payouts) do
      add_if_not_exists :retentions_cents, :integer, default: 0, null: false
    end
  end
end
