defmodule Ledgr.Domains.AumentaMiPension.Consultations do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.Consultations.Consultation

  def list_consultations(opts \\ []) do
    Consultation
    |> maybe_filter_status(opts[:status])
    |> maybe_search(opts[:search])
    |> order_by(desc: :assigned_at)
    |> Repo.all()
    |> Repo.preload([:customer, :agent])
  end

  def get_consultation!(id) do
    Consultation
    |> Repo.get!(id)
    |> Repo.preload([
      :customer,
      :agent,
      :calls,
      conversation: [:messages, :pension_case]
    ])
  end

  def get_consultation(id) do
    Consultation
    |> Repo.get(id)
    |> Repo.preload([:customer, :agent])
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
    |> Repo.preload([:customer, :agent])
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    from(c in query,
      join: cu in assoc(c, :customer),
      where: ilike(cu.full_name, ^term) or ilike(cu.display_name, ^term) or ilike(cu.phone, ^term)
    )
  end
end
