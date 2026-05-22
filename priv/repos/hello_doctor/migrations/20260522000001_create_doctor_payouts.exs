defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateDoctorPayouts do
  use Ecto.Migration

  def change do
    create table(:doctor_payouts) do
      add :doctor_id, references(:doctors, type: :string, on_delete: :restrict), null: false
      add :payout_date, :date, null: false
      add :amount_cents, :integer, null: false
      add :payment_method, :string, null: false, default: "bank_transfer"
      add :reference, :string
      add :notes, :text
      # journal_entry_id lives in the main accounting repo — store as plain integer
      # (no FK constraint, cross-database).
      add :journal_entry_id, :integer

      timestamps()
    end

    create index(:doctor_payouts, [:doctor_id])
    create index(:doctor_payouts, [:payout_date])

    create table(:doctor_payout_consultations) do
      add :doctor_payout_id,
          references(:doctor_payouts, on_delete: :delete_all),
          null: false

      add :consultation_id,
          references(:consultations, type: :string, on_delete: :restrict),
          null: false

      timestamps()
    end

    create unique_index(:doctor_payout_consultations, [:doctor_payout_id, :consultation_id],
             name: :doctor_payout_consultations_payout_consultation_index
           )

    create index(:doctor_payout_consultations, [:consultation_id])
  end
end
