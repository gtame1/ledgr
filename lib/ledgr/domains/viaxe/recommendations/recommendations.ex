defmodule Ledgr.Domains.Viaxe.Recommendations do
  @moduledoc """
  Context for managing curated travel recommendations (restaurants, hotels, tours, etc.)
  organized by city and category.
  """

  import Ecto.Query
  alias Ledgr.Repo
  alias Ledgr.Domains.Viaxe.Recommendations.Recommendation

  def list_recommendations(opts \\ []) do
    country = Keyword.get(opts, :country)
    city = Keyword.get(opts, :city)
    category = Keyword.get(opts, :category)

    Recommendation
    |> maybe_filter(:country, country)
    |> maybe_filter(:city, city)
    |> maybe_filter(:category, category)
    |> order_by([:country, :city, :category, :name])
    |> Repo.all()
  end

  def get_recommendation!(id), do: Repo.get!(Recommendation, id)

  def create_recommendation(attrs \\ %{}) do
    %Recommendation{}
    |> Recommendation.changeset(attrs)
    |> Repo.insert()
  end

  def update_recommendation(%Recommendation{} = rec, attrs) do
    rec
    |> Recommendation.changeset(attrs)
    |> Repo.update()
  end

  def delete_recommendation(%Recommendation{} = rec) do
    Repo.delete(rec)
  end

  def change_recommendation(%Recommendation{} = rec, attrs \\ %{}) do
    Recommendation.changeset(rec, attrs)
  end

  def country_options do
    Recommendation
    |> select([r], r.country)
    |> distinct(true)
    |> order_by(:country)
    |> Repo.all()
  end

  def city_options(country \\ nil) do
    Recommendation
    |> maybe_filter(:country, country)
    |> select([r], r.city)
    |> distinct(true)
    |> order_by(:city)
    |> Repo.all()
  end

  # ── Private ────────────────────────────────────────────────────────

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query
  defp maybe_filter(query, field, value), do: where(query, ^[{field, value}])
end
