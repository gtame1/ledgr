defmodule Ledgr.Domains.AumentaMiPension.CrmEntries do
  @moduledoc """
  Context for the Ledgr-owned CRM overlay (`lead_crm` table).
  One row per AMP lead (keyed by normalized 10-digit phone — see
  `Ledgr.Domains.AumentaMiPension.Phones.normalize/1`), holding:

    * **CRM pipeline** — `contact_stage`, `sales_stage`
    * **Four-axis state** — `funnel_stage`, `qualification_verdict`,
      `escalation_status`, `engagement_health`

  See `CrmEntry` for the value enums and labels.

  ## Phone-keying conventions

  Every `phone` argument is passed through `Phones.normalize/1` before
  use. Callers can pass raw phones in any of the source formats
  (`+5215522992238`, `5215522992238`, `5522992238`, `(552) 299-2238`)
  and they all collapse to the same `lead_crm.phone` row.

  Passing an unparseable phone (returns `nil` from `normalize/1`) is
  treated as "no lead exists" — `get_by_phone/1` returns nil,
  `upsert/2` returns `{:error, :invalid_phone}`.
  """

  alias Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry
  alias Ledgr.Domains.AumentaMiPension.Phones
  alias Ledgr.Repo

  @doc """
  Returns the CRM entry for `phone`, or nil if none exists yet.
  Accepts any phone format; normalizes internally.
  """
  def get_by_phone(phone) when is_binary(phone) do
    case Phones.normalize(phone) do
      nil -> nil
      normalized -> Repo.get_by(CrmEntry, phone: normalized)
    end
  end

  def get_by_phone(_), do: nil

  @doc """
  Inserts or updates the CRM entry for `phone` with the given attrs.
  Returns `{:ok, entry}`, `{:error, changeset}`, or
  `{:error, :invalid_phone}` if the phone can't be normalized.

  `attrs` should be a map with string keys (typical form params), e.g.
  `%{"funnel_stage" => "qualifying", "contact_stage" => "contacted"}`.
  Any subset of fields is allowed; omitted fields are left unchanged.
  """
  def upsert(phone, attrs) when is_binary(phone) and is_map(attrs) do
    case Phones.normalize(phone) do
      nil ->
        {:error, :invalid_phone}

      normalized ->
        entry = Repo.get_by(CrmEntry, phone: normalized) || %CrmEntry{}

        entry
        |> CrmEntry.changeset(Map.put(attrs, "phone", normalized))
        |> Repo.insert_or_update()
    end
  end

  # ── Per-field updaters ──────────────────────────────────────────────
  #
  # Thin wrappers over upsert/2 — one per writeable field. Prefer these
  # in code (jobs, tests, contexts) over calling upsert/2 with a
  # hand-built map; the form handler is the only legitimate caller
  # of the bulk upsert path.

  # CRM pipeline
  def update_contact_stage(phone, value), do: upsert(phone, %{"contact_stage" => value})
  def update_sales_stage(phone, value), do: upsert(phone, %{"sales_stage" => value})

  # Four-axis state
  def update_funnel_stage(phone, value),
    do: upsert(phone, %{"funnel_stage" => value})

  def update_qualification_verdict(phone, value),
    do: upsert(phone, %{"qualification_verdict" => value})

  def update_escalation_status(phone, value),
    do: upsert(phone, %{"escalation_status" => value})

  def update_engagement_health(phone, value),
    do: upsert(phone, %{"engagement_health" => value})

  @doc """
  Bulk read: returns a map of `phone => CrmEntry` for all phones that
  have an overlay row. Used by the Leads index to assemble lead rows
  without N+1 queries.
  """
  def map_by_phone(phones) when is_list(phones) do
    normalized =
      phones
      |> Enum.map(&Phones.normalize/1)
      |> Enum.reject(&is_nil/1)

    import Ecto.Query, only: [from: 2]

    from(c in CrmEntry, where: c.phone in ^normalized)
    |> Repo.all()
    |> Map.new(&{&1.phone, &1})
  end
end
