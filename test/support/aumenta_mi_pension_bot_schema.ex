defmodule Ledgr.Test.AumentaMiPensionBotSchema do
  @moduledoc """
  Creates the **bot-owned** Aumenta Mi Pensión tables in the test database.

  Per CLAUDE.md the bot owns `conversations`, `customers` and `consultations`
  (among others) and migrates them with its own tooling, so there is
  deliberately no Ledgr migration — one would create them in the bot's real
  database on the next deploy. The upshot was that the test database had no
  such tables at all, so the conversation pages could not be tested.

  Same contract as `Ledgr.Test.EscuelaDeDineroBotSchema`: raw DDL, run once
  from `test_helper.exs` before the repo enters sandbox mode, declaring only
  the columns our Ecto mirrors actually select. This proves our queries are
  well-formed and survive an empty table; it does not prove the mirrors match
  production — only the live database settles that.
  """

  @tables [
    """
    CREATE TABLE IF NOT EXISTS customers (
      id VARCHAR PRIMARY KEY,
      phone VARCHAR,
      display_name VARCHAR,
      full_name VARCHAR,
      date_of_birth VARCHAR,
      gender VARCHAR,
      curp VARCHAR,
      nss VARCHAR,
      weeks_contributed INTEGER,
      last_registered_salary DOUBLE PRECISION,
      current_employment_status VARCHAR,
      terms_accepted BOOLEAN DEFAULT false,
      terms_accepted_at TIMESTAMP,
      ley_73 BOOLEAN,
      last_imss_contribution_date VARCHAR,
      m40_monthly_budget DOUBLE PRECISION,
      -- Customer declares timestamps(inserted_at: :created_at).
      created_at TIMESTAMP NOT NULL DEFAULT now(),
      updated_at TIMESTAMP NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS conversations (
      id VARCHAR PRIMARY KEY,
      customer_id VARCHAR,
      status VARCHAR,
      funnel_stage VARCHAR,
      consultation_type VARCHAR,
      stripe_payment_intent_id VARCHAR,
      recording_consent_accepted_at TIMESTAMP,
      recording_consent_reply VARCHAR,
      consent_state VARCHAR,
      consent_retry_count INTEGER,
      data_review_sent_at TIMESTAMP,
      created_at TIMESTAMP,
      last_message_at TIMESTAMP(6),
      escalation_offered_at TIMESTAMPTZ,
      guide_budget_requested_at TIMESTAMPTZ,
      guide_delivered_at TIMESTAMPTZ,
      stall_count INTEGER DEFAULT 0,
      hallucinated_fallback_count INTEGER DEFAULT 0,
      qualification_verdict VARCHAR,
      escalation_status VARCHAR,
      engagement_health VARCHAR
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS consultations (
      id VARCHAR PRIMARY KEY,
      customer_id VARCHAR,
      agent_id VARCHAR,
      conversation_id VARCHAR,
      status VARCHAR,
      consultation_type VARCHAR DEFAULT 'messaging',
      assigned_at TIMESTAMP,
      accepted_at TIMESTAMP,
      completed_at TIMESTAMP,
      duration_minutes INTEGER,
      agent_notes VARCHAR,
      inactivity_ping_sent_at TIMESTAMP,
      payment_status VARCHAR,
      payment_amount DOUBLE PRECISION,
      payment_confirmed_at TIMESTAMP,
      stripe_payment_intent_id VARCHAR,
      last_broadcast_at TIMESTAMP,
      rejected_by_agents VARCHAR,
      awaiting_extension_response BOOLEAN DEFAULT false,
      search_extended_count INTEGER DEFAULT 0,
      audit_json VARCHAR,
      customer_summary VARCHAR,
      customer_rating INTEGER,
      customer_platform_rating INTEGER,
      customer_comment VARCHAR,
      agent_rating INTEGER,
      agent_platform_rating INTEGER,
      agent_comment VARCHAR,
      review_started_at TIMESTAMP
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS messages (
      id VARCHAR PRIMARY KEY,
      conversation_id VARCHAR,
      role VARCHAR,
      content VARCHAR,
      message_type VARCHAR,
      created_at TIMESTAMP
    )
    """
  ]

  @doc "Idempotent. Safe to call on every test run."
  def create! do
    Enum.each(@tables, &Ecto.Adapters.SQL.query!(Ledgr.Repos.AumentaMiPension, &1, []))
  end
end
