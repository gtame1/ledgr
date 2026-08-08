defmodule Ledgr.Domains.EscuelaDeDinero.Calidad do
  @moduledoc """
  Reading `policing_events` and the Kubo compliance trail.

  This is the compliance surface, not a debug log. Two of the four CRITICAL
  rules — `promesa_de_rendimiento` and `asesoria_en_inversiones` — describe
  activity that is regulated in Mexico; the other two (`solicitud_de_credenciales`,
  `kubo_link_ungated`) are hard brand rules. A CRITICAL here is a thing someone
  needs to look at, not a metric to trend.

  Read-only; the bot owns every row.
  """

  import Ecto.Query

  alias Ledgr.Domains.EscuelaDeDinero.KuboReferrals.KuboReferral
  alias Ledgr.Domains.EscuelaDeDinero.People.Person
  alias Ledgr.Domains.EscuelaDeDinero.PolicingEvents.PolicingEvent
  alias Ledgr.Repo

  @severity_order %{"CRITICAL" => 0, "WARNING" => 1, "INFO" => 2}

  def list_events(opts \\ %{}) do
    from(e in PolicingEvent,
      left_join: p in Person,
      on: p.id == e.person_id,
      order_by: [desc: e.ts],
      limit: 300,
      select: %{
        id: e.id,
        ts: e.ts,
        conv_id: e.conv_id,
        person_id: e.person_id,
        phone: p.phone,
        display_name: p.display_name,
        turn: e.turn,
        event_type: e.event_type,
        severity: e.severity,
        detail: e.detail,
        reply_snippet: e.reply_snippet,
        rule_version: e.rule_version,
        context: e.context
      }
    )
    |> apply_filters(opts)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {_k, v}, q when v in [nil, ""] -> q
      {:severity, severity}, q -> where(q, [e], e.severity == ^severity)
      {:event_type, type}, q -> where(q, [e], e.event_type == ^type)
      _, q -> q
    end)
  end

  @doc """
  Counts per rule, severest first then most frequent.

  Not windowed: a single `asesoria_en_inversiones` from four months ago still
  needs to be looked at, and a rolling window would quietly retire it.
  """
  def rule_summary do
    Repo.all(
      from e in PolicingEvent,
        group_by: [e.event_type, e.severity],
        select: %{event_type: e.event_type, severity: e.severity, count: count(e.id)}
    )
    |> Enum.sort_by(&{Map.get(@severity_order, &1.severity, 9), -&1.count})
  end

  @doc "Totals by severity, for the header chips."
  def severity_totals do
    Repo.all(from e in PolicingEvent, group_by: e.severity, select: {e.severity, count(e.id)})
    |> Map.new()
  end

  # ── Kubo ───────────────────────────────────────────────────────────

  def list_referrals do
    Repo.all(
      from k in KuboReferral,
        left_join: p in Person,
        on: p.id == k.person_id,
        order_by: [desc: k.sent_at],
        select: %{
          id: k.id,
          person_id: k.person_id,
          phone: p.phone,
          display_name: p.display_name,
          diagnostico_id: k.diagnostico_id,
          gate_reason: k.gate_reason,
          link_url: k.link_url,
          disclosure_message_id: k.disclosure_message_id,
          sent_at: k.sent_at,
          clicked_at: k.clicked_at,
          outcome: k.outcome,
          outcome_reported_at: k.outcome_reported_at
        }
    )
  end

  @doc """
  The compliance assertion, straight off the bot's own model docstring:
  a referral row carrying a `link_url` but no `disclosure_message_id` means an
  affiliate link shipped without the declaration that money changes hands.

  Should always be zero.
  """
  def referrals_sin_declaracion do
    Repo.all(
      from k in KuboReferral,
        left_join: p in Person,
        on: p.id == k.person_id,
        where: not is_nil(k.link_url) and is_nil(k.disclosure_message_id),
        order_by: [desc: k.sent_at],
        select: %{
          id: k.id,
          person_id: k.person_id,
          phone: p.phone,
          sent_at: k.sent_at
        }
    )
  end

  @doc """
  Counts per gate reason.

  How often the gate *refuses* is the number worth watching — a gate that never
  refuses isn't a gate, it's a funnel.
  """
  def gate_summary do
    Repo.all(
      from k in KuboReferral,
        group_by: k.gate_reason,
        order_by: [desc: count(k.id)],
        select: {k.gate_reason, count(k.id)}
    )
  end
end
