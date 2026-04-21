defmodule Ledgr.Domains.AumentaMiPension.AgentAssistantMessages.AgentAssistantMessage do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @timestamps_opts [type: :naive_datetime]

  schema "agent_assistant_messages" do
    field :role, :string
    field :content, :string
    field :tool_name, :string
    field :tool_args, :string

    belongs_to :agent, Ledgr.Domains.AumentaMiPension.Agents.Agent
    belongs_to :consultation, Ledgr.Domains.AumentaMiPension.Consultations.Consultation

    timestamps(inserted_at: :created_at, updated_at: false)
  end
end
