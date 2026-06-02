defmodule Ledgr.Repos.HelloDoctor.Migrations.AddConsultationFeeToDoctors do
  use Ecto.Migration

  @moduledoc """
  Per-doctor consultation fee (cents). Nullable — a NULL means
  "use the global default" (currently $100 MXN). The field is
  informational only for now; ConsultationAccounting / MonthlyReport /
  DoctorPayouts continue to use the hardcoded default until a
  follow-up wires the column through.
  """

  def change do
    alter table(:doctors) do
      add :consultation_fee_cents, :integer
    end
  end
end
