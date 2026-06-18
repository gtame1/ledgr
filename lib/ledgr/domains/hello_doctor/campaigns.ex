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
  The campaign-generation cutoff (Mexico City). On this date the Meta ad
  sets were refreshed with new emoji coding. The acquisition dashboard
  splits its funnel tables into a "before" era (legacy Meta + landing)
  and a "from" era (new Meta + landing), windowing each table's data at
  this boundary.
  """
  def cutoff, do: ~D[2026-06-17]

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
  Campaigns active in the **before-cutoff** era: legacy Meta ad sets
  (`started_on: nil`) plus the evergreen landing pages. These get the
  "Before #{inspect(~D[2026-06-17])}" funnel table, windowed to data
  before the cutoff.
  """
  def before_cutoff do
    Enum.filter(all(), &(&1.channel == :landing or is_nil(&1.started_on)))
  end

  @doc """
  Campaigns active in the **from-cutoff** era: the new Meta ad sets
  launched on the cutoff date plus the evergreen landing pages. These
  get the "From #{inspect(~D[2026-06-17])}" funnel table, windowed to
  data on/after the cutoff.

  Landing pages appear in both `before_cutoff/0` and `from_cutoff/0` —
  they run continuously, so their leads divide across the two tables at
  the cutoff boundary.
  """
  def from_cutoff do
    Enum.filter(all(), &(&1.channel == :landing or &1.started_on == cutoff()))
  end

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
