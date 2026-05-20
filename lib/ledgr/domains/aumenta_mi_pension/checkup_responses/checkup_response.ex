defmodule Ledgr.Domains.AumentaMiPension.CheckupResponses.CheckupResponse do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "checkup_responses" do
    field :created_at, :utc_datetime

    # Survey answers
    field :already_retired, :boolean
    field :birth_before_july_1997, :boolean
    field :weeks_contributed, :integer
    field :last_year_cotized, :string
    field :regimen_classification, :string
    field :has_afore, :boolean
    field :afore_name, :string
    field :imss_appointment_status, :string
    field :mission_progress, :map
    field :recommended_next_step, :string
    field :pension_type, :string
    field :desired_next_step, :string
    field :salary_known, :boolean
    field :salary_mode, :string
    field :last_salary_mxn, :decimal

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
    field :contact_birth_date, :date
    field :contact_nss, :string
    field :contact_curp, :string
  end
end
