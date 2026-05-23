defmodule Ledgr.Domains.AumentaMiPension.CrmEntries do
  @moduledoc """
  Context for the Ledgr-owned CRM overlay (`conversation_crm` table).
  One row per AMP conversation, holding:

    * **CRM pipeline** — `contact_stage`, `sales_stage`
    * **Four-axis state** — `funnel_stage`, `qualification_verdict`,
      `escalation_status`, `engagement_health`

  See `CrmEntry` for the value enums and labels.

  `upsert/2` accepts any subset of fields and is the primary write
  path (used by the form-driven UI). The `update_*` wrappers below
  are convenience for programmatic single-field writes — keep using
  them rather than `upsert/2` from contexts/jobs/tests so intent is
  obvious and a future cross-field invariant has a clear place to
  live.
  """

  alias Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry
  alias Ledgr.Repo

  @doc "Returns the CRM entry for a conversation, or nil if none exists yet."
  def get_by_conversation_id(conversation_id) when is_binary(conversation_id) do
    Repo.get_by(CrmEntry, conversation_id: conversation_id)
  end

  @doc """
  Inserts or updates the CRM entry for `conversation_id` with the given
  attrs. Returns `{:ok, entry}` or `{:error, changeset}`.

  `attrs` should be a map with string keys (typical form params), e.g.
  `%{"funnel_stage" => "qualifying", "contact_stage" => "contacted"}`.
  Any subset of fields is allowed; omitted fields are left unchanged.
  """
  def upsert(conversation_id, attrs) when is_binary(conversation_id) and is_map(attrs) do
    entry = get_by_conversation_id(conversation_id) || %CrmEntry{}

    entry
    |> CrmEntry.changeset(Map.put(attrs, "conversation_id", conversation_id))
    |> Repo.insert_or_update()
  end

  # ── Per-field updaters ──────────────────────────────────────────────
  #
  # Thin wrappers over upsert/2 — one per writeable field. Prefer these
  # in code (jobs, tests, contexts) over calling upsert/2 with a
  # hand-built map; the form handler is the only legitimate caller
  # of the bulk upsert path.

  # CRM pipeline
  def update_contact_stage(conv_id, value), do: upsert(conv_id, %{"contact_stage" => value})
  def update_sales_stage(conv_id, value), do: upsert(conv_id, %{"sales_stage" => value})

  # Four-axis state
  def update_funnel_stage(conv_id, value),
    do: upsert(conv_id, %{"funnel_stage" => value})

  def update_qualification_verdict(conv_id, value),
    do: upsert(conv_id, %{"qualification_verdict" => value})

  def update_escalation_status(conv_id, value),
    do: upsert(conv_id, %{"escalation_status" => value})

  def update_engagement_health(conv_id, value),
    do: upsert(conv_id, %{"engagement_health" => value})
end
