defmodule Ledgr.Repos.HelloDoctor.Migrations.AddPayDoctorToStripePayments do
  use Ecto.Migration

  @moduledoc """
  Adds the `pay_doctor` boolean on stripe_payments — the override that
  controls whether the linked consultation produces a doctor payable.

  Defaults to `true` (the doctor is paid). On refund we flip it to
  `false` unless the operator opts in to the "Still pay doctor"
  override. Manual edits from the admin UI can flip it later.

  Backfill: every historical refund flips to `pay_doctor = false` so
  the Doctor Payouts page and Weekly Report stop showing them as owed
  the moment they switch their filter from status-based to flag-based.
  """

  def change do
    alter table(:stripe_payments) do
      add :pay_doctor, :boolean, default: true, null: false
    end

    # Backfill — refunded historical rows match the pre-change default
    # of "doctor not paid on refund". `down` resets the column so a
    # rollback leaves no residue beyond the column drop above.
    execute(
      "UPDATE stripe_payments SET pay_doctor = false WHERE status = 'refunded'",
      "UPDATE stripe_payments SET pay_doctor = true"
    )
  end
end
