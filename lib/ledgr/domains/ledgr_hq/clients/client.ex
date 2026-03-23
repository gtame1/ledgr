defmodule Ledgr.Domains.LedgrHQ.Clients.Client do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ledgr.Domains.LedgrHQ.ClientSubscriptions.ClientSubscription

  @valid_statuses ~w(active trial paused churned)

  schema "clients" do
    field :name, :string
    field :domain_slug, :string
    field :status, :string, default: "active"
    field :started_on, :date
    field :ended_on, :date
    field :notes, :string

    has_many :client_subscriptions, ClientSubscription

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :status, :started_on]
  @optional_fields [:domain_slug, :ended_on, :notes]

  def changeset(client, attrs) do
    client
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
