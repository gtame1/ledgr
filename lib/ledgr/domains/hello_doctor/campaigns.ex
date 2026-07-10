defmodule Ledgr.Domains.HelloDoctor.Campaigns do
  @moduledoc """
  Meta Ad campaign definitions for HelloDoctor and the attribution
  logic that maps a patient's first WhatsApp message to a campaign.

  Each Meta ad (and landing-page CTA) uses WhatsApp's click-to-chat with
  a prefilled welcome message carrying a campaign-specific **emoji**. We
  attribute a conversation to a campaign when its first inbound user
  message contains that emoji.

  ## Why emoji-only (no phrase matching)

  We previously also required a distinctive phrase from the welcome
  template. Auditing real first-messages showed the phrase requirement
  was net-harmful: it silently dropped genuine ad clicks — patients edit
  the prefill ("mi hija" vs the template's "mi hijo"), delete the text
  but keep the emoji ("Hola 👋"), or the deployed ad text simply differs
  from spec (GAST shipped "he estado sintiéndome mal", not "llevo días
  sintiéndome mal"). Meanwhile it filtered almost no noise, because these
  emojis essentially never appear in an organic conversation opener — a
  brand-new chat starting with 🩺 or 🫠 came from an ad. The emoji alone
  is the reliable signal, and the mapping is 1:1 (every campaign uses a
  distinct emoji), so the CASE is unambiguous.

  The `phrase` field is kept as documentation of the expected welcome
  text (shown in the dashboard reference) — it is NOT used for matching.

  Adding a campaign: append an entry to `all/0` with a unique emoji. The
  detection CASE rebuilds itself from the list.
  """

  defstruct [
    :id,
    :label,
    :emoji,
    :campaign_set,
    :ad_set,
    :pain,
    # Reference only — the distinctive part of the prefilled welcome
    # message. Shown in the dashboard; NOT used for attribution.
    :phrase,
    # Acquisition channel. `:meta` = a Meta ad (era-bound — replaced when
    # the ad set is refreshed). `:landing` = an evergreen landing-page
    # CTA that runs continuously across campaign generations. The
    # dashboard splits campaigns into a "before" and a "from" era at the
    # cutoff date (see `cutoff/0`); landing-page campaigns are evergreen,
    # so they appear in BOTH eras with their data divided at the cutoff.
    channel: :meta,
    # Launch date (Mexico City). `nil` = a legacy/original Meta campaign
    # that predates the cutoff. New-generation campaigns set this to the
    # cutoff date. Detection and attribution are date-agnostic — this is
    # display grouping only.
    started_on: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          emoji: String.t(),
          campaign_set: String.t(),
          ad_set: String.t(),
          pain: String.t(),
          phrase: String.t(),
          channel: :meta | :landing,
          started_on: Date.t() | nil
        }

  @doc """
  The current Meta generation's launch date (Mexico City). On this date
  the Meta ad sets were refreshed with new emoji coding (see the cohort
  in `all/0`). Campaigns of that generation carry `started_on: cutoff()`.
  """
  def cutoff, do: ~D[2026-06-17]

  @doc """
  Tracking-window boundaries (Mexico City), ascending. Each boundary
  opens a new measurement window on the acquisition dashboard.

  The first boundary is when the current Meta generation launched
  (`cutoff/0`). Later boundaries are plain tracking cuts: they re-window
  the SAME live campaigns (no new ad sets) so ops can watch a fresh
  period without older leads diluting it. Add a date here to start a new
  window; if that window also introduces new ad sets, give those
  campaigns a matching `started_on` and they become its generation.
  """
  def cuts, do: [cutoff(), ~D[2026-06-24], ~D[2026-07-08]]

  @doc """
  Campaigns live in the generation that was current on `date`: the
  evergreen landing pages, plus the Meta ad sets of the latest generation
  launched on or before `date` (the original legacy set — `started_on:
  nil` — when `date` predates the first launch).
  """
  def generation_campaigns_at(%Date{} = date) do
    current_launch =
      all()
      |> Enum.map(& &1.started_on)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort({:asc, Date})
      |> Enum.filter(&(Date.compare(&1, date) != :gt))
      |> List.last()

    Enum.filter(all(), fn c ->
      cond do
        c.channel == :landing -> true
        is_nil(current_launch) -> is_nil(c.started_on)
        true -> c.started_on == current_launch
      end
    end)
  end

  @doc """
  The dashboard's tracking eras, oldest first. Each is a half-open
  window `[lower, upper)` between consecutive `cuts/0` boundaries (with
  open `nil` ends before the first / after the last cut), tagged with the
  ids of the campaigns live in that window. The acquisition page renders
  one funnel table per era.
  """
  def eras do
    sorted = Enum.sort(cuts(), {:asc, Date})
    earliest = hd(sorted)

    ([nil] ++ sorted ++ [nil])
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [lower, upper] ->
      rep = lower || Date.add(earliest, -1)

      %{
        lower: lower,
        upper: upper,
        campaign_ids: generation_campaigns_at(rep) |> Enum.map(& &1.id)
      }
    end)
  end

  @doc """
  All tracked campaigns. Each must use a unique emoji — that emoji is the
  attribution key. Order is the detection priority (first match wins) for
  the rare message that somehow contains two campaign emojis.
  """
  def all do
    [
      %__MODULE__{
        id: "gin_01",
        label: "Ginecología — Salud sexual",
        emoji: "👋",
        campaign_set: "Ginecología",
        ad_set: "GIN-01",
        pain: "Salud sexual general",
        phrase: "tengo una duda de salud"
      },
      %__MODULE__{
        id: "gin_02",
        label: "Ginecología — Pena/vergüenza",
        emoji: "🤫",
        campaign_set: "Ginecología",
        ad_set: "GIN-02",
        pain: "Pena/vergüenza",
        phrase: "tengo una pregunta"
      },
      %__MODULE__{
        id: "ped_01",
        label: "Pediatría — 3am del bebé",
        emoji: "👶",
        campaign_set: "Pediatría",
        ad_set: "PED-01",
        pain: "3am del bebé",
        phrase: "dudas sobre la salud de mi hijo"
      },
      %__MODULE__{
        id: "gen_01_thinking",
        label: "General — ¿Es grave? (🤔)",
        emoji: "🤔",
        campaign_set: "General",
        ad_set: "GEN-01",
        pain: "¿Es grave o no?",
        phrase: "necesito apoyo de un medico"
      },
      %__MODULE__{
        id: "gen_01_smile",
        label: "General — ¿Es grave? (🙂)",
        emoji: "🙂",
        campaign_set: "General",
        ad_set: "GEN-01",
        pain: "¿Es grave o no?",
        phrase: "podrian apoyarme con dudas de salud"
      },
      %__MODULE__{
        id: "awr_01",
        label: "Awareness — Video views",
        emoji: "⚕️",
        campaign_set: "Awareness",
        ad_set: "AWR-01",
        pain: "Video views",
        phrase: "vi su video, quiero info"
      },
      # ── Meta cohort launched 2026-06-17 ──────────────────────────
      # New emoji coding. Welcome messages (as deployed):
      #   🌼  "Hola, tengo una duda 🌼"
      #   🫠  "Hola, he estado sintiéndome mal 🫠"
      #   🤒  "Hola, mi bebé se siente mal 🤒"
      %__MODULE__{
        id: "gine_manchado",
        label: "Ginecología — Manchado",
        emoji: "🌼",
        campaign_set: "Ginecología",
        ad_set: "GINE-01",
        pain: "Manchado / sangrado",
        phrase: "tengo una duda",
        started_on: cutoff()
      },
      %__MODULE__{
        id: "gast_estomago",
        label: "Gastro — Estómago",
        emoji: "🫠",
        campaign_set: "Gastroenterología",
        ad_set: "GAST-01",
        pain: "Malestar estomacal",
        # Deployed ad text — differs from the original spec ("llevo días…").
        phrase: "he estado sintiéndome mal",
        started_on: cutoff()
      },
      %__MODULE__{
        id: "ped_bebe_enfermo",
        label: "Pediatría — Bebé enfermo",
        emoji: "🤒",
        campaign_set: "Pediatría",
        # Legacy PED-01 ("3am del bebé") still tracks history; this is a
        # distinct creative, so it gets its own ad-set code.
        ad_set: "PED-02",
        pain: "Bebé enfermo",
        phrase: "mi bebé se siente mal",
        started_on: cutoff()
      },
      # ── Meta cohort launched 2026-06-24 ──────────────────────────
      # New emoji coding; replaces the 2026-06-17 cohort as the current
      # generation. Welcome messages (as deployed):
      #   🌸  "Hola, tengo una duda 🌸"
      #   😕  "Hola, mi hijo se siente mal 😕"
      #   😖  "Hola, he estado sintiéndome mal 😖"
      #   😓  "Hola, no me he estado sintiendo bien 😓"
      #   🤕  "Hola, llevo días con molestias 🤕"
      #   🥼  "Hola, me gustaria hablar con un medico 🥼"
      %__MODULE__{
        id: "gine_duda",
        label: "Ginecología — Duda",
        emoji: "🌸",
        campaign_set: "Ginecología",
        ad_set: "GINE-02",
        pain: "Duda ginecológica",
        phrase: "tengo una duda",
        started_on: ~D[2026-06-24]
      },
      %__MODULE__{
        id: "ped_hijo",
        label: "Pediatría — Hijo enfermo",
        emoji: "😕",
        campaign_set: "Pediatría",
        ad_set: "PED-03",
        pain: "Hijo enfermo",
        phrase: "mi hijo se siente mal",
        started_on: ~D[2026-06-24]
      },
      %__MODULE__{
        id: "gast_malestar",
        label: "Gastro — Malestar",
        emoji: "😖",
        campaign_set: "Gastroenterología",
        ad_set: "GAST-02",
        pain: "Malestar general",
        phrase: "he estado sintiéndome mal",
        started_on: ~D[2026-06-24]
      },
      %__MODULE__{
        id: "cabeza",
        label: "Cabeza — Malestar",
        emoji: "😓",
        campaign_set: "Cabeza",
        ad_set: "CAB-01",
        pain: "No se siente bien",
        phrase: "no me he estado sintiendo bien",
        started_on: ~D[2026-06-24]
      },
      %__MODULE__{
        id: "urologia",
        label: "Urología — Molestias",
        emoji: "🤕",
        campaign_set: "Urología",
        ad_set: "URO-01",
        pain: "Molestias (días)",
        phrase: "llevo días con molestias",
        started_on: ~D[2026-06-24]
      },
      %__MODULE__{
        id: "medico_general",
        label: "General — Hablar con médico",
        emoji: "🥼",
        campaign_set: "General",
        ad_set: "GEN-02",
        pain: "Hablar con un médico",
        phrase: "me gustaria hablar con un medico",
        started_on: ~D[2026-06-24]
      },
      # ── Landing pages (evergreen — span every Meta generation) ───
      %__MODULE__{
        id: "lpc_01",
        label: "General — /consulta landing",
        emoji: "🩺",
        campaign_set: "General",
        ad_set: "LPC-01",
        pain: "From /consulta landing page",
        phrase: "busco una consulta médica",
        channel: :landing
      },
      %__MODULE__{
        id: "lph_01",
        label: "General — Home page CTA",
        emoji: "🙏",
        campaign_set: "General",
        ad_set: "LPH-01",
        pain: "From the home page CTA",
        phrase: "me interesa una consulta",
        channel: :landing
      }
    ]
  end

  @doc "Returns the campaign with the given `id`, or `nil`."
  def get(id), do: Enum.find(all(), &(&1.id == id))

  @doc """
  SQL CASE expression that maps a message-content column to a campaign
  id, or `NULL` if no campaign emoji is present. Pass the column name as
  `content_ref` — e.g. `"fm.content"`.

  Attribution is **emoji-only**: each campaign owns a unique emoji, so a
  single `LIKE '%emoji%'` per campaign suffices. Emojis carry no SQL
  quotes, so no escaping is needed.
  """
  def detection_case_sql(content_ref) do
    whens =
      all()
      |> Enum.map_join("\n        ", fn c ->
        "WHEN #{content_ref} LIKE '%#{c.emoji}%' THEN '#{c.id}'"
      end)

    "CASE\n        #{whens}\n        ELSE NULL\n      END"
  end
end
