defmodule Ledgr.Domains.HelloDoctor.Doctors.Doctor do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "doctors" do
    field :phone, :string
    field :name, :string
    field :specialty, :string
    field :cedula_profesional, :string
    field :university, :string
    field :years_experience, :integer
    field :email, :string
    field :is_available, :boolean, default: true
    field :accepts_video_calls, :boolean, default: true
    field :terms_accepted, :boolean, default: false
    field :terms_accepted_at, :utc_datetime
    field :extension_code, :string
    field :prescrypto_medic_id, :integer
    field :prescrypto_token, :string
    field :prescrypto_specialty_no, :string
    field :prescrypto_specialty_verified, :boolean, default: false
    field :prescrypto_synced_at, :utc_datetime
    # Medikit digital prescriptions (migrating off Prescrypto). Both columns
    # live in the shared Neon DB and are added out-of-band — Ledgr only syncs
    # the schema here, never migrates the doctors table. Populated by the
    # one-off MedikitProvisioning backfill: the HealthcareProvider id returned
    # by Medikit's POST /doctors, and the UTC timestamp at which the doctor's
    # professional license was validated + registered. NULL = not yet
    # provisioned (the backfill is idempotent on this column being NULL).
    field :medikit_healthcare_provider_id, :string
    field :medikit_license_validated_at, :utc_datetime
    # Structured doctor data required by Medikit's doctors-1.0.38 API that the
    # bot's onboarding never captured. All optional at the changeset level so
    # existing doctor CRUD keeps working; MedikitProvisioning enforces
    # completeness before it will register a doctor.
    field :first_name, :string
    field :paternal_surname, :string
    field :maternal_surname, :string
    field :birthdate, :date
    field :gender, :string
    field :tax_id, :string
    # Kept per-doctor for a possible future international expansion; Medikit
    # currently supports MX/CO. Falls back to the :medikit config default ("MX")
    # at send time when blank.
    field :address_country, :string
    field :address_state, :string
    field :address_city, :string
    field :address_line, :string
    field :address_zipcode, :string
    # Medikit specialty catalog id, chosen from the Medikit catalog dropdown.
    # Distinct from the free-text `specialty` (which drives bot routing).
    field :medikit_specialty_id, :string
    # Admin-confirmed: do we have the doctor's correct RFC on file for
    # CFDI invoicing? Flipped from the doctor show page.
    field :has_correct_rfc, :boolean, default: false
    # When set, the bot will not route new consultations to this doctor. Set
    # by admins via the Deactivate button on the doctor show page; cleared
    # via Reactivate. Distinct from `is_available` (doctor's own
    # "I'm available now" toggle).
    field :deactivated_at, :utc_datetime
    # Per-doctor consultation fee in whole MXN pesos. Owned by the bot
    # for the "direct" consultation flow; the value 0 means "no
    # per-doctor fee set — use the global default" (currently $100 MXN
    # for the "mvp"/"now" flow). The field is editable from the
    # doctor edit/new pages.
    field :consultation_fee_mxn, :integer, default: 0
    # Bot-owned. Precomputed `wa.me` click-to-chat deep link embedding
    # the doctor's `extension_code` (DR-XXXX). Used as the shareable
    # patient-onboarding link. NULL when the bot's
    # whatsapp_business_number is unconfigured. Read-only from Ledgr.
    field :referral_link, :string

    has_many :consultations, Ledgr.Domains.HelloDoctor.Consultations.Consultation
    has_many :prescriptions, Ledgr.Domains.HelloDoctor.Prescriptions.Prescription

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  @required ~w[id phone name specialty is_available]a
  @optional ~w[cedula_profesional university years_experience email accepts_video_calls terms_accepted terms_accepted_at extension_code prescrypto_medic_id prescrypto_token prescrypto_specialty_no prescrypto_specialty_verified prescrypto_synced_at deactivated_at has_correct_rfc consultation_fee_mxn referral_link medikit_healthcare_provider_id medikit_license_validated_at first_name paternal_surname maternal_surname birthdate gender tax_id address_country address_state address_city address_line address_zipcode medikit_specialty_id]a

  # Genders Medikit accepts (RAML Gender pattern). Countries Medikit supports
  # (RAML Country pattern ^(MX|CO)$). Mexican state codes (RAML State pattern).
  @genders ~w[Male Female Other]
  @countries ~w[MX CO]
  @mx_states ~w[AG BC BS CH CL CM CO CS CX DG GR GT HG JA ME MI MO NA NL OA PB QE QR SI SL SO TB TL TM VE YU ZA]

  def genders, do: @genders
  def countries, do: @countries
  def mx_states, do: @mx_states

  def changeset(doctor, attrs) do
    doctor
    |> cast(attrs, @required ++ @optional)
    |> normalize_phone()
    |> validate_number(:consultation_fee_mxn, greater_than_or_equal_to: 0)
    |> validate_medikit_fields()
    |> validate_required(@required)
    |> unique_constraint(:phone)
  end

  # Format/enum checks for the Medikit fields — applied only when a value is
  # present (the fields stay optional so partial doctor records still save).
  defp validate_medikit_fields(changeset) do
    changeset
    |> validate_inclusion(:gender, @genders)
    |> validate_inclusion(:address_country, @countries)
    |> validate_state_for_country()
    |> validate_format(:address_zipcode, ~r/^\d{5,10}$/,
      message: "must be 5–10 digits"
    )
  end

  # `@mx_states` only describes Mexico. Enforce it solely for MX doctors so a
  # future non-MX country (CO) isn't blocked by Mexican state codes; that
  # country's own state list/UI is a later addition.
  defp validate_state_for_country(changeset) do
    case get_field(changeset, :address_country) || "MX" do
      "MX" -> validate_inclusion(changeset, :address_state, @mx_states)
      _ -> changeset
    end
  end

  @doc """
  Returns the doctor's effective consultation fee in MXN. `0` (the
  unset default) falls back to the global $100; otherwise returns
  the stored per-doctor amount.
  """
  def effective_consultation_fee_mxn(%__MODULE__{consultation_fee_mxn: v}) when v in [nil, 0],
    do: 100

  def effective_consultation_fee_mxn(%__MODULE__{consultation_fee_mxn: v}), do: v

  defp normalize_phone(changeset) do
    case get_change(changeset, :phone) do
      nil -> changeset
      phone -> put_change(changeset, :phone, String.replace(phone, ~r/[^0-9]/, ""))
    end
  end

  @doc """
  True when the doctor satisfies every gate the bot checks before routing
  a consultation:

    * `terms_accepted == true`            — set by the doctor in the T&Cs flow
    * `is_available == true`              — set by the doctor via `/disponible`
    * `prescrypto_specialty_verified == true` — set by Prescrypto sync
    * `deactivated_at IS NULL`            — admin-controlled block

  All four must hold. Mirror of the bot's gating logic — if the bot adds
  another gate, update this and `eligibility_failures/1` in tandem.
  """
  def eligible_for_consultations?(%__MODULE__{} = d) do
    d.terms_accepted == true and
      d.is_available == true and
      d.prescrypto_specialty_verified == true and
      is_nil(d.deactivated_at)
  end

  @doc """
  Returns the human-readable list of gates a doctor is currently failing.
  Empty list means eligible. Used to populate the eligibility-badge tooltip.
  """
  def eligibility_failures(%__MODULE__{} = d) do
    []
    |> push_if(d.deactivated_at, "deactivated by admin")
    |> push_if(!d.is_available, "marked themselves unavailable")
    |> push_if(!d.terms_accepted, "hasn't accepted terms")
    |> push_if(!d.prescrypto_specialty_verified, "cédula not verified in Prescrypto")
    |> Enum.reverse()
  end

  defp push_if(list, falsy, _msg) when falsy in [nil, false], do: list
  defp push_if(list, _truthy, msg), do: [msg | list]
end
