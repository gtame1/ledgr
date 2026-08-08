defmodule Ledgr.Domains.EscuelaDeDinero.KuboReferrals.KuboReferral do
  @moduledoc """
  The affiliate emission ledger — a compliance trail, not a revenue record.
  Bot-owned (`kubo_referrals`) — read-only here. Carries no amounts.

  The row is inserted *before* the send, so the invariant worth asserting is:

      link_url IS NOT NULL AND disclosure_message_id IS NULL

  which means an affiliate link went out without the commercial-relationship
  declaration alongside it. That should always be zero.

  `clicked_at` and `outcome` have no writer yet (the `GET /r/kubo/:id` redirect
  route isn't implemented), and `outcome` is self-reported when it does land.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "kubo_referrals" do
    field :person_id, :string
    field :diagnostico_id, :string
    field :conversation_id, :string
    # Slug from kubo.GATE_REASONS. How often the gate REFUSES is the metric
    # worth watching — a gate that never refuses is a funnel, not a gate.
    field :gate_reason, :string
    field :link_url, :string
    # wamid of the declaration message. NULL + a link_url = compliance bug.
    field :disclosure_message_id, :string
    field :sent_at, :utc_datetime
    field :clicked_at, :utc_datetime
    # abrio_cuenta | no | unknown
    field :outcome, :string
    field :outcome_reported_at, :utc_datetime

    belongs_to :person, Ledgr.Domains.EscuelaDeDinero.People.Person, define_field: false
  end
end
