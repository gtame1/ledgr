defmodule Ledgr.Repos.HelloDoctor.Migrations.CreateSpecialties do
  use Ecto.Migration

  @specialties [
    "Medicina General",
    "Pediatría",
    "Ginecología y Obstetricia",
    "Medicina Interna",
    "Cardiología",
    "Dermatología",
    "Neurología",
    "Ortopedia y Traumatología",
    "Oftalmología",
    "Otorrinolaringología",
    "Psiquiatría",
    "Urología",
    "Gastroenterología",
    "Endocrinología",
    "Reumatología",
    "Neumología",
    "Nefrología",
    "Nutriología",
    "Psicología Clínica",
    "Cirugía General"
  ]

  def change do
    create table(:specialties) do
      add :name, :string, null: false
      add :is_active, :boolean, default: true, null: false
      timestamps(inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:specialties, [:name])

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(@specialties, fn name ->
        %{name: name, is_active: true, created_at: now}
      end)

    execute(
      fn -> repo().insert_all("specialties", rows, on_conflict: :nothing) end,
      fn -> :ok end
    )
  end
end
