defmodule Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "pension_cases" do
    field :goal, :string
    field :age, :integer
    field :weeks_contributed, :integer
    field :last_registered_salary, :float
    field :current_employment_status, :string
    field :years_to_retirement, :integer
    field :qualifies, :boolean
    field :qualification_reason, :string
    field :recommended_modalidad, :string
    field :current_projected_pension, :float
    field :m40_projected_pension, :float
    field :m40_target_sbc, :float
    field :m40_monthly_contribution, :float
    field :m40_duration_months, :integer
    field :simulation_delta_monthly, :float
    field :simulation_pdf_url, :string
    field :simulation_sent_at, :naive_datetime
    field :media_analyses, :string
    field :call_transcript, :string
    field :ai_summary, :string

    belongs_to :customer, Ledgr.Domains.AumentaMiPension.Customers.Customer
    belongs_to :conversation, Ledgr.Domains.AumentaMiPension.Conversations.Conversation

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end
end
