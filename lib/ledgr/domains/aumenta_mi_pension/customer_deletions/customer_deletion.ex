defmodule Ledgr.Domains.AumentaMiPension.CustomerDeletions.CustomerDeletion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:customer_id, :string, autogenerate: false}

  schema "customer_deletions" do
    field :phone, :string
    field :full_name, :string
    field :reason, :string
    field :deleted_by, :string
    field :deleted_at, :utc_datetime

    timestamps()
  end

  @required ~w[customer_id deleted_at]a
  @optional ~w[phone full_name reason deleted_by]a

  def changeset(deletion, attrs) do
    deletion
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end
end
