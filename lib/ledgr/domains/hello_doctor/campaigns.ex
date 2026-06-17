defmodule Ledgr.Domains.HelloDoctor.Campaigns do
  @moduledoc """
  Meta Ad campaign definitions for HelloDoctor and the attribution
  logic that maps a patient's first WhatsApp message to a campaign.

  Each Meta ad uses WhatsApp's click-to-chat with a prefilled welcome
  message containing a campaign-specific emoji + phrase. We attribute
  in two passes:

  1. **High-confidence**: emoji + phrase both match. The strongest
     signal — almost no false-positive risk.
  2. **Phrase-only fallback** (campaigns flagged `phrase_only_fallback`):
     the phrase alone is distinctive enough to attribute even when the
     patient stripped the emoji. Enabled for phrases like
     `dudas sobre la salud de mi hijo` (very ad-specific) but not for
     `tengo una pregunta` (too generic).

  Phrase matching is **accent-insensitive** via Postgres' `unaccent`
  extension (`médico` ↔ `medico`, `podrían` ↔ `podrian`). Emoji
  matching is byte-equal.

  Adding a campaign: append an entry to `all/0`. The detection CASE
  rebuilds itself from the list.
  """

  defstruct [
    :id,
    :label,
    :emoji,
    :campaign_set,
    :ad_set,
    :pain,
    :phrase,
    phrase_only_fallback: false,
    # Optional second anchor for campaigns that drift in practice
    # (patients insert/double words between phrase parts). When set,
    # detection matches a regex `phrase.{0,max_gap}anchor_2` instead
    # of a strict substring on `phrase` alone. Both anchors run
    # through unaccent() for accent insensitivity.
    anchor_2: nil,
    max_gap: 20,
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
          phrase_only_fallback: boolean(),
          anchor_2: String.t() | nil,
          max_gap: non_neg_integer(),
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
  All tracked campaigns. Order is the detection priority — first match
  wins in the SQL CASE. Put the most specific patterns first; common
  emojis last.
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
        phrase: "tengo una duda de salud",
        phrase_only_fallback: true
      },
      %__MODULE__{
        id: "gin_02",
        label: "Ginecología — Pena/vergüenza",
        emoji: "🤫",
        campaign_set: "Ginecología",
        ad_set: "GIN-02",
        pain: "Pena/vergüenza",
        phrase: "tengo una pregunta",
        # Phrase alone is too generic — could false-match organic chatter.
        phrase_only_fallback: false
      },
      %__MODULE__{
        id: "ped_01",
        label: "Pediatría — 3am del bebé",
        emoji: "👶",
        campaign_set: "Pediatría",
        ad_set: "PED-01",
        pain: "3am del bebé",
        phrase: "dudas sobre la salud de mi hijo",
        phrase_only_fallback: true
      },
      %__MODULE__{
        id: "gen_01_thinking",
        label: "General — ¿Es grave? (🤔)",
        emoji: "🤔",
        campaign_set: "General",
        ad_set: "GEN-01",
        pain: "¿Es grave o no?",
        # Two anchors tolerate the doubled-word case ("apoyo de de un").
        phrase: "necesito apoyo de",
        anchor_2: "un medico",
        phrase_only_fallback: true
      },
      %__MODULE__{
        id: "gen_01_smile",
        label: "General — ¿Es grave? (🙂)",
        emoji: "🙂",
        campaign_set: "General",
        ad_set: "GEN-01",
        pain: "¿Es grave o no?",
        # Two anchors tolerate inserted words ("con unas dudas").
        phrase: "podrian apoyarme",
        anchor_2: "dudas de salud",
        phrase_only_fallback: true
      },
      %__MODULE__{
        id: "awr_01",
        label: "Awareness — Video views",
        emoji: "⚕️",
        campaign_set: "Awareness",
        ad_set: "AWR-01",
        pain: "Video views",
        phrase: "vi su video, quiero info",
        phrase_only_fallback: true
      },
      # ── Meta cohort launched 2026-06-17 ──────────────────────────
      # New emoji coding. Welcome messages:
      #   🌼  "Hola, tengo una duda 🌼"
      #   🫠  "Hola, llevo días sintiéndome mal 🫠"
      #   🤒  "Hola, mi bebé se siente mal 🤒"
      %__MODULE__{
        id: "gine_manchado",
        label: "Ginecología — Manchado",
        emoji: "🌼",
        campaign_set: "Ginecología",
        ad_set: "GINE-01",
        pain: "Manchado / sangrado",
        phrase: "tengo una duda",
        # "tengo una duda" is generic (and a substring of GIN-01's
        # "tengo una duda de salud") — require the 🌼 emoji so it can't
        # false-match organic chatter or steal credit from GIN-01.
        phrase_only_fallback: false,
        started_on: cutoff()
      },
      %__MODULE__{
        id: "gast_estomago",
        label: "Gastro — Estómago",
        emoji: "🫠",
        campaign_set: "Gastroenterología",
        ad_set: "GAST-01",
        pain: "Malestar estomacal",
        phrase: "llevo días sintiéndome mal",
        phrase_only_fallback: true,
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
        phrase_only_fallback: true,
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
        phrase_only_fallback: true,
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
        # "me interesa una consulta" is fairly common phrasing —
        # require the emoji to avoid false positives.
        phrase_only_fallback: false,
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
  SQL CASE expression that maps a message-content column to a
  campaign id, or `NULL` if no match. Pass the column name as
  `content_ref` — e.g. `"fm.content"`.

  Two passes inside the CASE:

  1. **Emoji + phrase** (strict) — all campaigns, in declared order.
  2. **Phrase-only fallback** — only for campaigns with
     `phrase_only_fallback: true`, in declared order.

  Both passes use `unaccent(content)` for accent-insensitive matching
  (`médico` ↔ `medico`, `podrían` ↔ `podrian`).

  Campaigns with `anchor_2` set use a regex (`~*`) with up to
  `max_gap` chars between the two anchors — tolerates word-injection
  / word-doubling drift (e.g. `apoyo de de un medico` → still matches
  `apoyo de.{0,N}un medico`). Campaigns without `anchor_2` fall back
  to a simple `ILIKE` substring on `phrase`.
  """
  def detection_case_sql(content_ref) do
    strict =
      all()
      |> Enum.map_join("\n        ", fn c ->
        "WHEN #{content_ref} LIKE '%#{c.emoji}%' " <>
          "AND #{phrase_predicate_sql(content_ref, c)} " <>
          "THEN '#{c.id}'"
      end)

    fallback =
      all()
      |> Enum.filter(& &1.phrase_only_fallback)
      |> Enum.map_join("\n        ", fn c ->
        "WHEN #{phrase_predicate_sql(content_ref, c)} THEN '#{c.id}'"
      end)

    "CASE\n        #{strict}\n        #{fallback}\n        ELSE NULL\n      END"
  end

  # Builds the SQL predicate that checks if `content_ref` contains the
  # campaign's phrase (and optional anchor_2). Accent-insensitive.
  defp phrase_predicate_sql(content_ref, %__MODULE__{anchor_2: nil} = c) do
    "unaccent(#{content_ref}) ILIKE unaccent('%#{escape(c.phrase)}%')"
  end

  defp phrase_predicate_sql(content_ref, %__MODULE__{anchor_2: a2} = c) do
    pattern = "#{regex_escape(c.phrase)}.{0,#{c.max_gap}}#{regex_escape(a2)}"
    "unaccent(#{content_ref}) ~* unaccent('#{escape(pattern)}')"
  end

  defp escape(s), do: String.replace(s, "'", "''")

  # Escape POSIX regex metachars in user-supplied anchors. Our phrases
  # are clean ASCII words today, but this guards against future
  # anchors that include punctuation like '.' or '?'.
  defp regex_escape(s) do
    Regex.escape(s)
  end
end
