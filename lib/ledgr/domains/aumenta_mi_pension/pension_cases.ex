defmodule Ledgr.Domains.AumentaMiPension.PensionCases do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.PensionCases.PensionCase

  def list_pension_cases(opts \\ []) do
    PensionCase
    |> maybe_filter_qualifies(opts[:qualifies])
    |> maybe_filter_modalidad(opts[:modalidad])
    |> maybe_search(opts[:search])
    |> order_by(desc: :created_at)
    |> Repo.all()
    |> Repo.preload([:customer])
  end

  def get_pension_case!(id) do
    PensionCase
    |> Repo.get!(id)
    |> Repo.preload([:customer, conversation: [:messages]])
  end

  def modalidad_options do
    PensionCase
    |> where([p], not is_nil(p.recommended_modalidad))
    |> distinct(true)
    |> select([p], p.recommended_modalidad)
    |> Repo.all()
    |> Enum.sort()
  end

  def count_all, do: Repo.aggregate(PensionCase, :count)

  def count_qualified do
    PensionCase
    |> where([p], p.qualifies == true)
    |> Repo.aggregate(:count)
  end

  defp maybe_filter_qualifies(query, nil), do: query
  defp maybe_filter_qualifies(query, ""), do: query
  defp maybe_filter_qualifies(query, "true"), do: where(query, [p], p.qualifies == true)
  defp maybe_filter_qualifies(query, "false"), do: where(query, [p], p.qualifies == false)
  defp maybe_filter_qualifies(query, _), do: query

  defp maybe_filter_modalidad(query, nil), do: query
  defp maybe_filter_modalidad(query, ""), do: query

  defp maybe_filter_modalidad(query, modalidad),
    do: where(query, [p], p.recommended_modalidad == ^modalidad)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    term = "%#{search}%"

    from(p in query,
      join: cu in assoc(p, :customer),
      where:
        ilike(cu.full_name, ^term) or ilike(cu.display_name, ^term) or ilike(cu.phone, ^term) or
          ilike(cu.curp, ^term) or ilike(cu.nss, ^term)
    )
  end
end
