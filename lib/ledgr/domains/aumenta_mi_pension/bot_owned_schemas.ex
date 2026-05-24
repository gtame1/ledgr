defmodule Ledgr.Domains.AumentaMiPension.BotOwnedSchemas do
  @moduledoc """
  Canonical registry of Ecto schemas that mirror **bot-owned** tables
  on the AMP database. The bot service is the source of truth for these
  tables (migrations live in the bot's repo, not ours); we mirror them
  here so Ledgr can read/write through Ecto.

  This list is consumed by `mix amp.schema_drift`, which compares each
  schema's declared fields against `information_schema.columns` on the
  live DB and fails the build when a column we depend on has been
  dropped/renamed (the class of bug that took down prod on 2026-05-23).

  Add new bot tables here as the bot ships them. Don't include
  Ledgr-owned tables — those drift with our own migrations, which we
  control.
  """

  @schemas [
    Ledgr.Domains.AumentaMiPension.Agents.Agent,
    Ledgr.Domains.AumentaMiPension.AgentAssistantMessages.AgentAssistantMessage,
    Ledgr.Domains.AumentaMiPension.CalculadoraSubmissions.CalculadoraSubmission,
    Ledgr.Domains.AumentaMiPension.CheckupResponses.CheckupResponse,
    Ledgr.Domains.AumentaMiPension.Consultations.Consultation,
    Ledgr.Domains.AumentaMiPension.ConsultationCalls.ConsultationCall,
    Ledgr.Domains.AumentaMiPension.Conversations.Conversation,
    Ledgr.Domains.AumentaMiPension.Customers.Customer,
    Ledgr.Domains.AumentaMiPension.Messages.Message,
    Ledgr.Domains.AumentaMiPension.OutboundMessages.OutboundMessage,
    Ledgr.Domains.AumentaMiPension.Payments.Payment,
    Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase
  ]

  @doc "All bot-owned Ecto schema modules we mirror."
  def schemas, do: @schemas
end
