defmodule Ledgr.Domains.AumentaMiPension.ConversationBuckets.ConversationBucket do
  @moduledoc """
  Ledgr-owned operator overlay for an AMP conversation. One row per
  `conversation_id`, holding two independent kinds of annotation:

    * six boolean tag flags ("buckets"), and
    * `case_notes` — free-text operator comments about the case,
      meant to be fed to the bot as extra context.

  Operators edit both on the conversation detail page; the bot never
  writes here (and must be taught to *read* `case_notes` for the
  context to take effect — that's a bot-side change).

  The six buckets map to AMP's service lines:

    * `asesoria`                   — Asesoría
    * `demanda`                    — Demanda
    * `traspaso_afore`             — Traspaso Afore
    * `diagnostico_gratuito`       — Diagnóstico Gratuito
    * `financiamiento_retroactivo` — Financiamiento Retroactivo
    * `credito_pensionado`         — Crédito Pensionado

  `conversations` is bot-owned (see CLAUDE.md), so the tags live in this
  separate Ledgr-owned table keyed by `conversation_id` rather than as
  columns on `conversations`.

  ## Editing the buckets

  `@buckets` below is the single source of truth — a list of
  `{field, label_es}` pairs. The schema fields, changeset cast list,
  and the checkbox card all derive from it. Adding/removing a bucket is
  a field + migration + one-line list change.
  """

  use Ecto.Schema
  import Ecto.Changeset

  # {field, label_es} — single source of truth, in display order.
  @buckets [
    {:asesoria, "Asesoría"},
    {:demanda, "Demanda"},
    {:traspaso_afore, "Traspaso Afore"},
    {:diagnostico_gratuito, "Diagnóstico Gratuito"},
    {:financiamiento_retroactivo, "Financiamiento Retroactivo"},
    {:credito_pensionado, "Crédito Pensionado"}
  ]

  @bucket_fields Enum.map(@buckets, &elem(&1, 0))

  @primary_key {:conversation_id, :string, autogenerate: false}

  schema "conversation_buckets" do
    field :asesoria, :boolean, default: false
    field :demanda, :boolean, default: false
    field :traspaso_afore, :boolean, default: false
    field :diagnostico_gratuito, :boolean, default: false
    field :financiamiento_retroactivo, :boolean, default: false
    field :credito_pensionado, :boolean, default: false

    # Free-text operator comments about the case, surfaced to the bot
    # as additional context (bot must read it; see @moduledoc).
    field :case_notes, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [:conversation_id, :case_notes | @bucket_fields])
    |> validate_required([:conversation_id])
    |> update_change(:case_notes, &blank_to_nil/1)
  end

  # Treat an all-whitespace textarea as "no note" so the bot sees a
  # clean NULL rather than an empty string.
  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc "List of `{field, label}` pairs, in display order."
  def buckets, do: @buckets

  @doc "List of the six bucket field atoms."
  def bucket_fields, do: @bucket_fields
end
