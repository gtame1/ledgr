defmodule Ledgr.Test.HelloDoctorBotSchema do
  @moduledoc """
  Adds the **bot-owned** Hello Doctor columns to the test database.

  Unlike Escuela de Dinero — where no table has a Ledgr migration — HD's
  `conversations` table *is* created by `20260406000001_create_hello_doctor_schema`
  for local development. But the bot has since added columns of its own
  (bot ADR-019/ADR-059: the operator quality marks and case notes), and those
  correctly have no Ledgr migration: writing one would try to alter the bot's
  real table on the next deploy.

  The result was that the mirror in `Conversations.Conversation` selected twelve
  columns the test database did not have, so *every* query against HD
  conversations died with `undefined_column` — which is why the conversation
  pages had no tests at all.

  So: idempotent `ADD COLUMN IF NOT EXISTS`, run once from `test_helper.exs`
  before the repo enters sandbox mode. This is a stand-in for the bot's schema,
  not a copy of it — it only proves our queries are well-formed and survive an
  empty table. The live database is what settles whether the mirror is right.
  """

  @statements [
    """
    ALTER TABLE conversations
      ADD COLUMN IF NOT EXISTS quality_signal VARCHAR,
      ADD COLUMN IF NOT EXISTS corpus_candidate BOOLEAN DEFAULT false,
      ADD COLUMN IF NOT EXISTS quality_marked_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS quality_marked_by VARCHAR,
      ADD COLUMN IF NOT EXISTS quality_notes VARCHAR,
      ADD COLUMN IF NOT EXISTS failure_category VARCHAR,
      ADD COLUMN IF NOT EXISTS first_bad_message_id VARCHAR,
      ADD COLUMN IF NOT EXISTS exemplary_message_id VARCHAR,
      ADD COLUMN IF NOT EXISTS corrected_response VARCHAR,
      ADD COLUMN IF NOT EXISTS operator_notes VARCHAR,
      ADD COLUMN IF NOT EXISTS operator_notes_updated_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS operator_notes_updated_by VARCHAR
    """
  ]

  @doc "Idempotent. Safe to call on every test run."
  def create! do
    Enum.each(@statements, &Ecto.Adapters.SQL.query!(Ledgr.Repos.HelloDoctor, &1, []))
  end
end
