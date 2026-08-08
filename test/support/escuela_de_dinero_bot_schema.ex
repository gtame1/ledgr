defmodule Ledgr.Test.EscuelaDeDineroBotSchema do
  @moduledoc """
  Creates the **bot-owned** Escuela de Dinero tables in the test database.

  Every table this domain reads is owned by `escuela-de-dinero-bot` and migrated
  by its Alembic, so there is deliberately no Ledgr migration for them — one
  would create them in the bot's real database on the next deploy. But the test
  database still needs them to exist, or every controller test dies with
  `undefined_table` before it can assert anything.

  So: raw DDL, run once from `test_helper.exs`, outside the SQL sandbox. Only
  the columns our Ecto schemas actually select are declared — this is a stand-in
  for the bot's schema, not a copy of it. `mix edd.schema_drift` against the real
  database is what proves the mirrors are correct; this only proves our queries
  are well-formed and survive an empty table.
  """

  @tables [
    """
    CREATE TABLE IF NOT EXISTS people (
      id VARCHAR PRIMARY KEY,
      phone VARCHAR NOT NULL,
      display_name VARCHAR,
      etapa VARCHAR NOT NULL DEFAULT 'nuevo',
      mode VARCHAR NOT NULL DEFAULT 'diagnostico',
      etapa_regression_reason VARCHAR,
      terms_accepted BOOLEAN NOT NULL DEFAULT false,
      terms_accepted_at TIMESTAMPTZ,
      ai_disclosed_at TIMESTAMPTZ,
      latest_diagnostico_id VARCHAR,
      memoria VARCHAR,
      memoria_updated_at TIMESTAMPTZ,
      opted_out_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS conversations (
      id VARCHAR PRIMARY KEY,
      person_id VARCHAR NOT NULL,
      status VARCHAR NOT NULL DEFAULT 'active',
      initiated_by VARCHAR NOT NULL DEFAULT 'person',
      opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      last_inbound_at TIMESTAMPTZ,
      last_message_at TIMESTAMPTZ,
      freeform_until TIMESTAMPTZ,
      closed_at TIMESTAMPTZ,
      etapa_at_open VARCHAR,
      session_summary VARCHAR
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS messages (
      id VARCHAR PRIMARY KEY,
      conversation_id VARCHAR NOT NULL,
      role VARCHAR NOT NULL,
      content VARCHAR NOT NULL,
      message_type VARCHAR NOT NULL DEFAULT 'text',
      wamid VARCHAR,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS diagnosticos (
      id VARCHAR PRIMARY KEY,
      person_id VARCHAR NOT NULL,
      started_in_conversation_id VARCHAR,
      version INTEGER NOT NULL DEFAULT 1,
      status VARCHAR NOT NULL DEFAULT 'in_progress',
      schema_version VARCHAR NOT NULL DEFAULT 'v1',
      started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      confirmed_at TIMESTAMPTZ,
      playback_sent_at TIMESTAMPTZ,
      completed_at TIMESTAMPTZ,
      abandoned_at TIMESTAMPTZ,
      dias_sin_facturar INTEGER,
      headline JSONB NOT NULL DEFAULT '{}'::jsonb,
      respuestas JSONB NOT NULL DEFAULT '{}'::jsonb,
      areas JSONB NOT NULL DEFAULT '{}'::jsonb,
      movimientos JSONB NOT NULL DEFAULT '[]'::jsonb
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS movimientos (
      id VARCHAR PRIMARY KEY,
      diagnostico_id VARCHAR NOT NULL,
      person_id VARCHAR NOT NULL,
      orden INTEGER NOT NULL,
      area VARCHAR NOT NULL,
      titulo VARCHAR NOT NULL,
      accion_hoy VARCHAR NOT NULL,
      estado VARCHAR NOT NULL DEFAULT 'pendiente',
      due_at TIMESTAMPTZ,
      last_checkin_at TIMESTAMPTZ,
      checkin_count INTEGER NOT NULL DEFAULT 0,
      completed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS policing_events (
      id VARCHAR PRIMARY KEY,
      ts TIMESTAMPTZ NOT NULL DEFAULT now(),
      conv_id VARCHAR,
      person_id VARCHAR,
      turn INTEGER,
      event_type VARCHAR NOT NULL,
      severity VARCHAR NOT NULL,
      detail VARCHAR,
      reply_snippet VARCHAR,
      rule_version VARCHAR NOT NULL DEFAULT 'v1.0',
      context JSONB NOT NULL DEFAULT '{}'::jsonb
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS outbound_messages (
      id VARCHAR PRIMARY KEY,
      phone VARCHAR NOT NULL,
      message_type VARCHAR NOT NULL DEFAULT 'text',
      status VARCHAR NOT NULL DEFAULT 'sent',
      conversation_id VARCHAR,
      emitter VARCHAR,
      sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      delivered_at TIMESTAMPTZ,
      read_at TIMESTAMPTZ,
      error_detail VARCHAR
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS kubo_referrals (
      id VARCHAR PRIMARY KEY,
      person_id VARCHAR NOT NULL,
      diagnostico_id VARCHAR NOT NULL,
      conversation_id VARCHAR,
      gate_reason VARCHAR NOT NULL,
      link_url VARCHAR NOT NULL,
      disclosure_message_id VARCHAR,
      sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      clicked_at TIMESTAMPTZ,
      outcome VARCHAR,
      outcome_reported_at TIMESTAMPTZ
    )
    """
  ]

  @doc "Idempotent. Safe to call on every test run."
  def create! do
    Enum.each(@tables, &Ecto.Adapters.SQL.query!(Ledgr.Repos.EscuelaDeDinero, &1, []))
  end
end
