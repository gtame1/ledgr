defmodule Ledgr.Domains.VolumeStudio.Consultations do
  @moduledoc """
  Context module for managing Volume Studio consultations.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting

  @doc """
  Returns a list of consultations.

  Options:
    - `:status` — filter by status string
    - `:from` — filter sessions scheduled after this datetime
    - `:to` — filter sessions scheduled before this datetime
  """
  def list_consultations(opts \\ []) do
    status = Keyword.get(opts, :status)
    from_dt = Keyword.get(opts, :from)
    to_dt = Keyword.get(opts, :to)

    Consultation
    |> maybe_filter_status(status)
    |> maybe_filter_from(from_dt)
    |> maybe_filter_to(to_dt)
    |> order_by(desc: :scheduled_at)
    |> preload([:customer, :instructor])
    |> Repo.all()
  end

  @doc "Gets a single consultation with customer and instructor preloaded. Raises if not found."
  def get_consultation!(id) do
    Consultation
    |> preload([:customer, :instructor])
    |> Repo.get!(id)
  end

  @doc "Returns a changeset for the given consultation and attrs."
  def change_consultation(%Consultation{} = consultation, attrs \\ %{}) do
    Consultation.changeset(consultation, attrs)
  end

  @doc "Creates a consultation."
  def create_consultation(attrs \\ %{}) do
    %Consultation{}
    |> Consultation.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a consultation."
  def update_consultation(%Consultation{} = consultation, attrs) do
    consultation
    |> Consultation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Records payment for a consultation.

  In a transaction:
    1. Sets paid_at to today's date
    2. Creates journal entry: DR Cash / CR Consultation Revenue + optionally CR IVA Payable
  """
  def record_payment(%Consultation{paid_at: nil} = consultation) do
    Repo.transaction(fn ->
      updated =
        consultation
        |> Consultation.changeset(%{paid_at: Date.utc_today()})
        |> Repo.update!()

      VolumeStudioAccounting.record_consultation_payment(updated)

      updated
    end)
  end

  def record_payment(%Consultation{} = _consultation) do
    {:error, :already_paid}
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, dt), do: where(query, [c], c.scheduled_at >= ^dt)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, dt), do: where(query, [c], c.scheduled_at <= ^dt)
end
