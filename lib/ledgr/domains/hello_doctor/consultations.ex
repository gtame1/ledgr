defmodule Ledgr.Domains.HelloDoctor.Consultations do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation

  def list_consultations(opts \\ []) do
    Consultation
    |> maybe_filter_status(opts[:status])
    |> maybe_search(opts[:search])
    |> order_by(desc: :assigned_at)
    |> Repo.all()
    |> Repo.preload([:patient, :doctor])
  end

  def get_consultation!(id) do
    Consultation
    |> Repo.get!(id)
    |> Repo.preload([
      :patient,
      :doctor,
      :prescriptions,
      :calls,
      conversation: [:medical_record, :messages]
    ])
  end

  def get_consultation(id) do
    Consultation
    |> Repo.get(id)
    |> Repo.preload([:patient, :doctor])
  end

  @doc """
  Records a Stripe payment for a consultation. Updates the consultation
  payment fields and creates the accounting journal entry in a transaction.
  """
  def record_stripe_payment(%Consultation{} = consultation, attrs) do
    consultation = Repo.preload(consultation, [:patient, :doctor])
    amount = attrs[:payment_amount] || attrs["payment_amount"] || 0.0

    Repo.transaction(fn ->
      # Update consultation payment fields
      changeset =
        consultation
        |> Ecto.Changeset.change(%{
          payment_status: "paid",
          payment_amount: amount,
          payment_confirmed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        })

      case Repo.update(changeset) do
        {:ok, updated} ->
          updated = Repo.preload(updated, [:patient, :doctor])

          # Create accounting journal entry
          case Ledgr.Domains.HelloDoctor.ConsultationAccounting.record_payment(
                 updated,
                 amount,
                 stripe_session_id: attrs[:stripe_session_id]
               ) do
            {:ok, _entry} -> updated
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_consultation(%Consultation{} = consultation, attrs) do
    consultation
    |> Consultation.changeset(attrs)
    |> Repo.update()
  end

  def update_status(%Consultation{} = consultation, new_status) do
    attrs =
      case new_status do
        "active" -> %{status: new_status, accepted_at: NaiveDateTime.utc_now()}
        "completed" -> %{status: new_status, completed_at: NaiveDateTime.utc_now()}
        _ -> %{status: new_status}
      end

    update_consultation(consultation, attrs)
  end

  def change_consultation(%Consultation{} = consultation, attrs \\ %{}) do
    Consultation.changeset(consultation, attrs)
  end

  def statuses, do: Consultation.statuses()

  def count_active do
    Consultation
    |> where([c], c.status in ~w[pending assigned active])
    |> Repo.aggregate(:count)
  end

  def list_recent(limit) do
    Consultation
    |> order_by(desc: :assigned_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload([:patient, :doctor])
  end

  def payment_stats(opts \\ []) do
    start_date = opts[:start_date] || opts[:from_date]
    end_date = opts[:end_date] || opts[:to_date]

    base =
      Consultation
      |> maybe_filter_date_range(start_date, end_date)

    total_revenue =
      base
      |> where([c], c.payment_status in ~w[paid confirmed])
      |> Repo.aggregate(:sum, :payment_amount) || 0.0

    total_consultations =
      base
      |> where([c], c.payment_status in ~w[paid confirmed])
      |> Repo.aggregate(:count)

    total_refunds =
      base
      |> where([c], c.payment_status == "refunded")
      |> Repo.aggregate(:sum, :payment_amount) || 0.0

    total_fees = total_revenue * 0.15

    %{
      total_revenue: total_revenue,
      total_fees: total_fees,
      total_refunds: total_refunds,
      total_consultations: total_consultations
    }
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query
  defp maybe_search(query, search) do
    term = "%#{search}%"
    from(c in query,
      join: p in assoc(c, :patient),
      where: ilike(p.full_name, ^term) or ilike(p.display_name, ^term) or ilike(p.phone, ^term)
    )
  end

  defp maybe_filter_date_range(query, nil, _), do: query
  defp maybe_filter_date_range(query, _, nil), do: query
  defp maybe_filter_date_range(query, start_date, end_date) do
    where(query, [c], fragment("?::date", c.assigned_at) >= ^start_date and fragment("?::date", c.assigned_at) <= ^end_date)
  end
end
