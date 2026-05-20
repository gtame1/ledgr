defmodule Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions.CalculadoraSubmission do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "calculadora_submissions" do
    field :created_at, :utc_datetime

    # Inputs
    field :birth_date, :date
    field :weeks_contributed, :integer
    field :daily_salary_imss_mxn, :decimal
    field :target_retirement_age, :integer
    field :desired_monthly_pension_mxn, :decimal
    field :available_savings_mxn, :decimal
    field :has_spouse, :boolean
    field :salary_mode, :string

    # Outputs
    field :estimated_monthly_pension_mxn, :decimal
    field :estimated_annual_pension_mxn, :decimal
    field :pension_without_m40_mxn, :decimal
    field :net_gain_20yr_mxn, :decimal
    field :total_invested_mxn, :decimal
    field :optimal_retirement_age, :integer
    field :uma_level, :integer

    # Attribution
    field :utm_source, :string
    field :utm_medium, :string
    field :utm_campaign, :string
    field :user_agent, :string
    field :ip_hash, :string
    field :referrer, :string

    # Contact (lead capture)
    field :contact_name, :string
    field :contact_phone, :string
    field :contact_email, :string
    field :payment_preference, :string
  end
end
