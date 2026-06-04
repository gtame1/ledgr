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
  @optional ~w[cedula_profesional university years_experience email accepts_video_calls terms_accepted terms_accepted_at extension_code prescrypto_medic_id prescrypto_token prescrypto_specialty_no prescrypto_specialty_verified prescrypto_synced_at deactivated_at has_correct_rfc consultation_fee_mxn]a

  def changeset(doctor, attrs) do
    doctor
    |> cast(attrs, @required ++ @optional)
    |> normalize_phone()
    |> validate_number(:consultation_fee_mxn, greater_than_or_equal_to: 0)
    |> validate_required(@required)
    |> unique_constraint(:phone)
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
