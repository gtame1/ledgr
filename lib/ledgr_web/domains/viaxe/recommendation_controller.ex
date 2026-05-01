defmodule LedgrWeb.Domains.Viaxe.RecommendationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.Recommendations
  alias Ledgr.Domains.Viaxe.Recommendations.Recommendation

  def index(conn, params) do
    opts = [
      country: params["country"],
      city: params["city"],
      category: params["category"]
    ]

    recommendations = Recommendations.list_recommendations(opts)
    countries = Recommendations.country_options()

    render(conn, :index,
      recommendations: recommendations,
      countries: countries,
      current_country: params["country"],
      current_city: params["city"],
      current_category: params["category"]
    )
  end

  def show(conn, %{"id" => id}) do
    recommendation = Recommendations.get_recommendation!(id)
    render(conn, :show, recommendation: recommendation)
  end

  def new(conn, _params) do
    changeset = Recommendations.change_recommendation(%Recommendation{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/recommendations"))
  end

  def create(conn, %{"recommendation" => rec_params}) do
    case Recommendations.create_recommendation(rec_params) do
      {:ok, _rec} ->
        conn
        |> put_flash(:info, "Recommendation added successfully.")
        |> redirect(to: dp(conn, "/recommendations"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/recommendations"))
    end
  end

  def edit(conn, %{"id" => id}) do
    rec = Recommendations.get_recommendation!(id)
    changeset = Recommendations.change_recommendation(rec)

    render(conn, :edit,
      recommendation: rec,
      changeset: changeset,
      action: dp(conn, "/recommendations/#{id}")
    )
  end

  def update(conn, %{"id" => id, "recommendation" => rec_params}) do
    rec = Recommendations.get_recommendation!(id)

    case Recommendations.update_recommendation(rec, rec_params) do
      {:ok, _rec} ->
        conn
        |> put_flash(:info, "Recommendation updated successfully.")
        |> redirect(to: dp(conn, "/recommendations"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          recommendation: rec,
          changeset: changeset,
          action: dp(conn, "/recommendations/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    rec = Recommendations.get_recommendation!(id)
    {:ok, _} = Recommendations.delete_recommendation(rec)

    conn
    |> put_flash(:info, "Recommendation deleted.")
    |> redirect(to: dp(conn, "/recommendations"))
  end
end

defmodule LedgrWeb.Domains.Viaxe.RecommendationHTML do
  use LedgrWeb, :html

  embed_templates "recommendation_html/*"

  def category_label("restaurant"), do: "🍽 Restaurant"
  def category_label("hotel"), do: "🏨 Hotel"
  def category_label("bar"), do: "🍸 Bar"
  def category_label("tour"), do: "🗺 Tour"
  def category_label("experience"), do: "⭐ Experience"
  def category_label("shopping"), do: "🛍 Shopping"
  def category_label("spa"), do: "💆 Spa"
  def category_label("beach"), do: "🏖 Beach"
  def category_label("museum"), do: "🏛 Museum"
  def category_label("other"), do: "📌 Other"
  def category_label(c), do: String.capitalize(c || "")
end
