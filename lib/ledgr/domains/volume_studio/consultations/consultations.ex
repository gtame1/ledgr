defmodule Ledgr.Domains.VolumeStudio.Consultations do
  @moduledoc """
  Context module for managing Volume Studio consultations.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Consultations.Consultation
  alias Ledgr.Domains.VolumeStudio.Accounting.VolumeStudioAccounting
  alias Ledgr.Core.Accounting.JournalEntry

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
    |> where([c], is_nil(c.deleted_at))
    |> maybe_filter_status(status)
    |> maybe_filter_from(from_dt)
    |> maybe_filter_to(to_dt)
    |> order_by(desc: :scheduled_at)
    |> preload([:customer])
    |> Repo.all()
  end

  @doc "Gets a single consultation with customer preloaded. Raises if not found."
  def get_consultation!(id) do
    from(c in Consultation, where: c.id == ^id and is_nil(c.deleted_at))
    |> preload([:customer])
    |> Repo.one!()
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
  Returns a payment summary map for a consultation.

  Keys: :amount_cents, :iva_cents, :total_cents, :outstanding_cents, :paid
  """
  def payment_summary(%Consultation{} = consultation) do
    amount = consultation.amount_cents
    iva = consultation.iva_cents || 0
    total = amount + iva
    paid = not is_nil(consultation.paid_at)
    outstanding = if paid, do: 0, else: total

    %{
      amount_cents: amount,
      iva_cents: iva,
      total_cents: total,
      paid: paid,
      outstanding_cents: outstanding
    }
  end

  @doc """
  Records a consultation payment with full payment details.

  In a transaction:
    1. Sets paid_at to the given payment date
    2. Creates journal entry: DR Cash / CR Consultation Revenue + optionally CR IVA Payable

  Options:
    - `:payment_date` — defaults to today
    - `:method`       — payment method string (stored in journal entry description)
    - `:note`         — optional note for the journal entry
  """
  def record_payment(consultation, amount_cents, opts \\ [])

  def record_payment(%Consultation{paid_at: nil} = consultation, amount_cents, opts) do
    payment_date = Keyword.get(opts, :payment_date, LedgrWeb.Helpers.DomainHelpers.today_mx())
    note = Keyword.get(opts, :note)
    paid_to_account_code = Keyword.get(opts, :paid_to_account_code, "1000")

    Repo.transaction(fn ->
      updated =
        consultation
        |> Consultation.changeset(%{paid_at: payment_date})
        |> Repo.update!()

      VolumeStudioAccounting.record_consultation_payment(updated, %{
        amount_cents: amount_cents,
        payment_date: payment_date,
        note: note,
        paid_to_account_code: paid_to_account_code
      })

      updated
    end)
  end

  def record_payment(%Consultation{}, _amount_cents, _opts), do: {:error, :already_paid}

  @doc """
  Returns all consultation_payment journal entries for a given consultation, newest first.
  Each entry has :journal_lines preloaded with :account.
  """
  def list_payments_for_consultation(%Consultation{id: id}) do
    prefix = "vs_consult_payment_#{id}%"

    from(je in JournalEntry,
      where: like(je.reference, ^prefix),
      order_by: [desc: je.date, desc: je.inserted_at],
      preload: [journal_lines: :account]
    )
    |> Repo.all()
  end

  @doc "Updates the status of a consultation."
  def update_status(%Consultation{} = consultation, status) do
    consultation
    |> Consultation.changeset(%{status: status})
    |> Repo.update()
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, status: ^status)

  defp maybe_filter_from(query, nil), do: query
  defp maybe_filter_from(query, dt), do: where(query, [c], c.scheduled_at >= ^dt)

  defp maybe_filter_to(query, nil), do: query
  defp maybe_filter_to(query, dt), do: where(query, [c], c.scheduled_at <= ^dt)
end
