defmodule Ledgr.Domains.AumentaMiPension.Leads do
  @moduledoc """
  Unified read API for the AMP "lead" view — joins the three lead-source
  tables (`customers`, `checkup_responses`, `calculadora_submissions`)
  by normalized phone, plus the operator overlay (`lead_crm`).

  See `Ledgr.Domains.AumentaMiPension.Leads.Lead` for the projected
  struct shape.

  Lead identity = `Phones.normalize/1` of any source's phone column.
  All cross-source joins happen on that canonical form.
  """

  import Ecto.Query

  alias Ledgr.Domains.AumentaMiPension.{
    CalculadoraSubmissions.CalculadoraSubmission,
    CheckupResponses.CheckupResponse,
    Conversations.Conversation,
    CrmEntries,
    Customers.Customer,
    Leads.Lead,
    Phones
  }

  alias Ledgr.Repo

  # ── Legacy → new lead-vocab funnel_stage mapping ────────────────────
  #
  # The bot's `conversations.funnel_stage` is mid-migration (some rows
  # have the new five-value vocab, most still have legacy values).
  # For the Lead's effective funnel_stage when no operator overlay is
  # set, project the bot's value onto the new vocab via this map.
  #
  # Confirmed with the user on 2026-05-23; see the plan file at
  # ~/.claude/plans/next-i-think-we-partitioned-badger.md.
  @bot_funnel_to_lead %{
    # New vocab — use directly.
    "intake" => "intake",
    "qualifying" => "qualifying",
    "terminal" => "terminal",
    "escalating" => "escalating",
    "closed" => "closed",
    # Legacy → new.
    "greeting" => "intake",
    "education" => "intake",
    "data_collection" => "intake",
    "qualification" => "qualifying",
    "simulation_sent" => "qualifying",
    "guide_offered" => "terminal",
    "guide_delivered" => "terminal",
    "guide_paid" => "terminal",
    "agent_offered" => "escalating",
    "agent_search" => "escalating",
    "agent_recommended" => "escalating",
    "consultation_active" => "closed",
    "consultation_complete" => "closed",
    "payment_link_sent" => "closed",
    "completed" => "closed"
  }

  @doc """
  Returns the **effective** funnel_stage for a Lead, with source.

  Precedence:
    1. `lead_crm.funnel_stage` (operator overlay) — wins when set.
    2. Latest conversation's `funnel_stage`, mapped legacy → new vocab.
    3. Default `"intake"` (calculadora-only / checkup-only / unmapped).

  Returns `{stage_string, source_atom}` where `source_atom` is one of
  `:operator`, `:bot`, `:default`. The detail page uses the source
  atom to badge where the displayed value came from.
  """
  def effective_funnel_stage(%Lead{crm_entry: %{funnel_stage: stage}})
      when is_binary(stage) and stage != "" do
    {stage, :operator}
  end

  def effective_funnel_stage(%Lead{latest_conversation: %{funnel_stage: stage}})
      when is_binary(stage) and stage != "" do
    case Map.get(@bot_funnel_to_lead, stage) do
      nil -> {"intake", :default}
      mapped -> {mapped, :bot}
    end
  end

  def effective_funnel_stage(%Lead{}), do: {"intake", :default}

  @doc """
  Same overlay-as-override rule as `effective_funnel_stage/1`, applied
  to the `qualification_verdict` axis. Returns `{verdict, source}` or
  `{nil, :none}` when nothing is set on either side. Useful on list /
  card views that want to surface the verdict at a glance.
  """
  def effective_verdict(%Lead{crm_entry: %{qualification_verdict: v}})
      when is_binary(v) and v != "" do
    {v, :operator}
  end

  def effective_verdict(%Lead{latest_conversation: %{qualification_verdict: v}})
      when is_binary(v) and v != "" do
    {v, :bot}
  end

  def effective_verdict(_), do: {nil, :none}

  @doc """
  Lists all leads, with everything we know about each phone loaded.

  Options:
    * `:funnel_stage` — filter to leads whose effective funnel_stage
      matches the given new-vocab value.
    * `:source` — keep only leads whose `sources` intersect with the
      given list (e.g. `[:conversation, :checkup]`).
    * `:search` — case-insensitive substring match against name, phone,
      or email across all sources.
    * `:order_by` — `:last_activity_desc` (default).

  Strategy: 4-5 batched queries, group everything by normalized phone
  in Elixir, build `Lead` structs. Acceptable up to a few thousand
  rows; if this gets slow, add per-source DB-side normalization
  (generated column or expression index) — see TODO.md.
  """
  def list_leads(opts \\ []) do
    customers = Repo.all(from c in Customer, where: not is_nil(c.phone))

    conversations =
      Repo.all(
        from c in Conversation,
          preload: [:customer],
          order_by: [desc: c.last_message_at]
      )

    checkups =
      Repo.all(
        from c in CheckupResponse,
          where: not is_nil(c.contact_phone),
          order_by: [desc: c.created_at]
      )

    calculadoras =
      Repo.all(
        from c in CalculadoraSubmission,
          where: not is_nil(c.contact_phone),
          order_by: [desc: c.created_at]
      )

    # Bucket each source by its normalized phone.
    customers_by_phone = bucket(customers, & &1.phone)

    conversations_by_phone =
      bucket(conversations, fn conv -> conv.customer && conv.customer.phone end)

    checkups_by_phone = bucket(checkups, & &1.contact_phone)
    calculadoras_by_phone = bucket(calculadoras, & &1.contact_phone)

    all_phones =
      [
        customers_by_phone,
        conversations_by_phone,
        checkups_by_phone,
        calculadoras_by_phone
      ]
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    crm_by_phone = CrmEntries.map_by_phone(all_phones)

    all_phones
    |> Enum.map(fn phone ->
      build_lead(phone, %{
        customers: customers_by_phone[phone] || [],
        conversations: conversations_by_phone[phone] || [],
        checkups: checkups_by_phone[phone] || [],
        calculadoras: calculadoras_by_phone[phone] || [],
        crm_entry: crm_by_phone[phone]
      })
    end)
    |> apply_filters(opts)
    |> sort_leads(opts[:order_by] || :last_activity_desc)
  end

  @doc """
  Phones of the leads immediately adjacent to `lead`, computed
  against a **precomputed** leads list (the caller is expected to
  already have one from `list_leads/1`).

  Prefer this over `neighbors/2` whenever the caller is going to use
  `list_leads/1` anyway — it avoids a second pass over every source
  table on the same request. The lead show controller uses this
  to halve its source-table scans.

  See `neighbors/2` for semantic details (prev = newer, next = older).
  """
  def neighbors_in(leads, %Lead{phone: phone}) when is_list(leads) do
    case Enum.find_index(leads, &(&1.phone == phone)) do
      nil ->
        %{prev_phone: nil, next_phone: nil}

      i ->
        prev_lead = if i > 0, do: Enum.at(leads, i - 1)
        next_lead = if i < length(leads) - 1, do: Enum.at(leads, i + 1)

        %{
          prev_phone: prev_lead && prev_lead.phone,
          next_phone: next_lead && next_lead.phone
        }
    end
  end

  @doc """
  Convenience: looks up a lead in a precomputed list by phone (any
  format). Returns nil when the phone doesn't normalize or doesn't
  appear in the list.
  """
  def find_lead_by_phone_in(leads, phone) when is_list(leads) do
    case Phones.normalize(phone) do
      nil -> nil
      normalized -> Enum.find(leads, &(&1.phone == normalized))
    end
  end

  @doc """
  Adds detail-page preloads to a lead's conversations (`:messages`,
  `:consultations`, `:pension_case`). The index-page `list_leads/1`
  only preloads `:customer` on conversations — light-touch for the
  table view. The detail page needs the heavier picture, but only
  for ONE lead, so we target it here instead of widening the index
  query.

  No-op for leads with zero conversations (calculadora-only or
  checkup-only).
  """
  def enrich_lead(%Lead{conversations: []} = lead), do: lead

  def enrich_lead(%Lead{conversations: convs} = lead) do
    conv_ids = Enum.map(convs, & &1.id)

    enriched =
      from(c in Conversation,
        where: c.id in ^conv_ids,
        preload: [:customer, :messages, :consultations, :pension_case],
        order_by: [desc: c.last_message_at]
      )
      |> Repo.all()

    %{lead | conversations: enriched, latest_conversation: List.first(enriched)}
  end

  @doc """
  Phones of the leads immediately adjacent to `lead` in the same
  filtered ordering used by `list_leads/1`. Standalone variant —
  re-runs `list_leads/1` internally.

  Prefer `neighbors_in/2` when the caller already has the listing
  in hand. Kept for callers without a precomputed list.
  """
  def neighbors(%Lead{} = lead, opts \\ []) do
    leads = list_leads(opts)
    neighbors_in(leads, lead)
  end

  @doc """
  Fetches a single Lead by phone (any format). Returns nil if the
  phone can't be normalized or matches nothing.
  """
  def get_lead_by_phone(phone) do
    normalized = Phones.normalize(phone)

    if is_nil(normalized) do
      nil
    else
      do_get_lead_by_phone(normalized)
    end
  end

  defp do_get_lead_by_phone(normalized) do
    # Per-source filter at the application level (the source phone
    # columns are unnormalized, so we can't `WHERE` on the normalized
    # form without a SQL function). For lead counts in the hundreds
    # this is cheap; revisit if it bites.
    customer =
      from(c in Customer, where: not is_nil(c.phone))
      |> Repo.all()
      |> Enum.find(&(Phones.normalize(&1.phone) == normalized))

    conversations =
      from(c in Conversation,
        preload: [:customer, :messages, :consultations, :pension_case],
        order_by: [desc: c.last_message_at]
      )
      |> Repo.all()
      |> Enum.filter(&(&1.customer && Phones.normalize(&1.customer.phone) == normalized))

    checkups =
      from(c in CheckupResponse,
        where: not is_nil(c.contact_phone),
        order_by: [desc: c.created_at]
      )
      |> Repo.all()
      |> Enum.filter(&(Phones.normalize(&1.contact_phone) == normalized))

    calculadoras =
      from(c in CalculadoraSubmission,
        where: not is_nil(c.contact_phone),
        order_by: [desc: c.created_at]
      )
      |> Repo.all()
      |> Enum.filter(&(Phones.normalize(&1.contact_phone) == normalized))

    crm_entry = CrmEntries.get_by_phone(normalized)

    if customer == nil and conversations == [] and checkups == [] and calculadoras == [] do
      nil
    else
      build_lead(normalized, %{
        customers: List.wrap(customer),
        conversations: conversations,
        checkups: checkups,
        calculadoras: calculadoras,
        crm_entry: crm_entry
      })
    end
  end

  # ── Internal helpers ────────────────────────────────────────────────

  defp bucket(rows, getter) do
    rows
    |> Enum.reduce(%{}, fn row, acc ->
      case Phones.normalize(getter.(row)) do
        nil -> acc
        phone -> Map.update(acc, phone, [row], &[row | &1])
      end
    end)
    # Each bucket's rows were prepended, so they're in reverse insert order;
    # but the underlying lists were already ordered by the source query,
    # so reverse-twice-is-a-noop. We end up with newest-first per bucket.
  end

  defp build_lead(phone, %{
         customers: customers,
         conversations: conversations,
         checkups: checkups,
         calculadoras: calculadoras,
         crm_entry: crm_entry
       }) do
    sources =
      []
      |> add_if(conversations != [], :conversation)
      |> add_if(checkups != [], :checkup)
      |> add_if(calculadoras != [], :calculadora)
      |> MapSet.new()

    customer = List.first(customers)
    latest_conversation = List.first(conversations)

    %Lead{
      phone: phone,
      display_name: best_name(customer, conversations, checkups, calculadoras),
      sources: sources,
      customer: customer,
      conversations: conversations,
      checkup_responses: checkups,
      calculadora_submissions: calculadoras,
      crm_entry: crm_entry,
      last_activity_at: last_activity(conversations, checkups, calculadoras),
      latest_conversation: latest_conversation
    }
  end

  defp add_if(list, true, item), do: [item | list]
  defp add_if(list, false, _), do: list

  # Priority order for display name: customer.full_name > customer.display_name
  # > any conversation's contact (none modeled) > checkup contact_name >
  # calculadora contact_name.
  defp best_name(customer, _conversations, checkups, calculadoras) do
    candidates =
      [
        customer && customer.full_name,
        customer && customer.display_name,
        first_non_nil(checkups, & &1.contact_name),
        first_non_nil(calculadoras, & &1.contact_name)
      ]

    Enum.find(candidates, fn v -> v not in [nil, ""] end)
  end

  defp first_non_nil(list, getter) do
    Enum.find_value(list, fn item ->
      case getter.(item) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp last_activity(conversations, checkups, calculadoras) do
    candidates =
      Enum.map(conversations, & &1.last_message_at) ++
        Enum.map(checkups, & &1.created_at) ++
        Enum.map(calculadoras, & &1.created_at)

    candidates
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  # ── Filtering / sorting ─────────────────────────────────────────────

  defp apply_filters(leads, opts) do
    leads
    |> filter_by_funnel_stage(opts[:funnel_stage])
    |> filter_by_source(opts[:source])
    |> filter_by_search(opts[:search])
  end

  defp filter_by_funnel_stage(leads, nil), do: leads
  defp filter_by_funnel_stage(leads, ""), do: leads

  defp filter_by_funnel_stage(leads, stage) do
    Enum.filter(leads, fn lead ->
      {effective, _source} = effective_funnel_stage(lead)
      effective == stage
    end)
  end

  defp filter_by_source(leads, nil), do: leads
  defp filter_by_source(leads, []), do: leads

  defp filter_by_source(leads, sources) when is_list(sources) do
    wanted = MapSet.new(sources)
    Enum.filter(leads, &(not MapSet.disjoint?(&1.sources, wanted)))
  end

  defp filter_by_search(leads, nil), do: leads
  defp filter_by_search(leads, ""), do: leads

  defp filter_by_search(leads, query) when is_binary(query) do
    needle = String.downcase(query)

    Enum.filter(leads, fn lead ->
      haystack =
        [
          lead.phone,
          lead.display_name,
          lead.customer && lead.customer.full_name,
          lead.customer && lead.customer.display_name,
          first_non_nil(lead.checkup_responses, & &1.contact_email),
          first_non_nil(lead.calculadora_submissions, & &1.contact_email)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&String.downcase/1)
        |> Enum.join(" ")

      String.contains?(haystack, needle)
    end)
  end

  defp sort_leads(leads, :last_activity_desc) do
    Enum.sort_by(leads, & &1.last_activity_at, {:desc, NaiveDateTime})
  end

  defp sort_leads(leads, _), do: leads
end
