defmodule Ledgr.Domains.HelloDoctor.Campaigns do
  @moduledoc """
  Meta Ad campaign definitions for HelloDoctor and the attribution
  logic that maps a patient's first WhatsApp message to a campaign.

  Each Meta ad uses WhatsApp's click-to-chat with a prefilled welcome
  message containing a campaign-specific emoji + phrase. When a patient
  clicks the ad, the bot receives that exact message as the first user
  inbound. We attribute the resulting conversation to the campaign by
  matching emoji AND a distinctive phrase from the template — both
  required, so common organic greetings (`Hola 🙂`, `Hola 👋`) don't
  bleed into the funnel.

  This is the "now"/"mvp" tenant only; "direct"-flow conversations
  enter via a different patient-picks-doctor path and aren't ad-driven.

  Adding a campaign: append an entry to `all/0` with a unique `id`,
  display fields, and the emoji+phrase pair. The detection CASE
  rebuilds itself from the list.
  """

  defstruct [:id, :label, :emoji, :campaign_set, :ad_set, :pain, :phrase]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          emoji: String.t(),
          campaign_set: String.t(),
          ad_set: String.t(),
          pain: String.t(),
          phrase: String.t()
        }

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
      %__MODULE__{
        id: "lpc_01",
        label: "General — /consulta landing",
        emoji: "🩺",
        campaign_set: "General",
        ad_set: "LPC-01",
        pain: "From /consulta landing page",
        phrase: "busco una consulta médica"
      },
      %__MODULE__{
        id: "lph_01",
        label: "General — Home page CTA",
        emoji: "🏠",
        campaign_set: "General",
        ad_set: "LPH-01",
        pain: "From the home page CTA",
        phrase: "me interesa una consulta"
      }
    ]
  end

  @doc "Returns the campaign with the given `id`, or `nil`."
  def get(id) do
    Enum.find(all(), &(&1.id == id))
  end

  @doc """
  SQL CASE expression that maps a message-content column to a
  campaign id, or `NULL` if no match. Pass the column name (already
  quoted) as `content_ref` — e.g. `"first_msg.content"`.

  Returns the SQL fragment as a string. Both the emoji AND the phrase
  must appear in the content for a match (case-insensitive on the
  phrase; emoji match is byte-equal via `LIKE`).
  """
  def detection_case_sql(content_ref) do
    clauses =
      all()
      |> Enum.map(fn c ->
        "WHEN #{content_ref} LIKE '%#{c.emoji}%' AND #{content_ref} ILIKE '%#{escape(c.phrase)}%' THEN '#{c.id}'"
      end)
      |> Enum.join("\n        ")

    "CASE\n        #{clauses}\n        ELSE NULL\n      END"
  end

  defp escape(s), do: String.replace(s, "'", "''")
end
