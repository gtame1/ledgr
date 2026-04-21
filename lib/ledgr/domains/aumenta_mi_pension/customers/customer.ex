defmodule Ledgr.Domains.AumentaMiPension.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "customers" do
    field :phone, :string
    field :display_name, :string
    field :full_name, :string
    field :date_of_birth, :string
    field :gender, :string
    field :curp, :string
    field :nss, :string
    field :weeks_contributed, :integer
    field :last_registered_salary, :float
    field :current_employment_status, :string
    field :terms_accepted, :boolean, default: false
    field :terms_accepted_at, :naive_datetime
    field :ley_73, :boolean
    field :last_imss_contribution_date, :string

    has_many :consultations, Ledgr.Domains.AumentaMiPension.Consultations.Consultation
    has_many :conversations, Ledgr.Domains.AumentaMiPension.Conversations.Conversation
    has_many :pension_cases, Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase

    timestamps(inserted_at: :created_at, updated_at: :updated_at)
  end

  @required ~w[id]a
  @optional ~w[phone display_name full_name date_of_birth gender curp nss weeks_contributed last_registered_salary current_employment_status terms_accepted terms_accepted_at ley_73 last_imss_contribution_date]a

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end

  def name(%__MODULE__{full_name: full_name, display_name: display_name}) do
    full_name || display_name || "Unknown"
  end
end
