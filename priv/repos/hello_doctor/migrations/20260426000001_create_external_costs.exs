defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateExternalCosts do
  use Ecto.Migration

  def change do
    create table(:external_costs) do
      add :service,       :string,  null: false
      add :date,          :date,    null: false
      add :amount_usd,    :float,   null: false, default: 0.0
      add :units,         :float
      add :unit_type,     :string
      add :model,         :string
      add :raw_response,  :map
      add :synced_at,     :utc_datetime, null: false

      timestamps()
    end

    # Per-model rows (OpenAI): unique on (service, date, model)
    create unique_index(:external_costs, [:service, :date, :model],
      where: "model IS NOT NULL",
      name: :external_costs_service_date_model_index
    )

    # Summary rows (Whereby, AWS, etc.): unique on (service, date)
    create unique_index(:external_costs, [:service, :date],
      where: "model IS NULL",
      name: :external_costs_service_date_index
    )
  end
end
