defmodule LedgrWeb.Domains.HelloDoctor.ReviewController do
  use LedgrWeb, :controller

  import Ecto.Query, warn: false

  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Reviews

  def index(conn, params) do
    today = Ledgr.Domains.HelloDoctor.today()
    start_date = parse_date(params["start_date"]) || Date.add(today, -30)
    end_date = parse_date(params["end_date"]) || today
    doctor_id = blank_to_nil(params["doctor_id"])
    rating_filter = blank_to_nil(params["rating_filter"])
    comments_only = params["comments_only"] == "true"
    sort = params["sort"] || "date"
    dir = params["dir"] || default_dir(sort)

    rows =
      Reviews.list_reviews(start_date, end_date,
        doctor_id: doctor_id,
        rating_filter: rating_filter,
        comments_only: comments_only,
        sort: sort,
        dir: dir
      )

    totals = Reviews.summarize(rows)

    doctors = Ledgr.Repo.all(from d in Doctor, order_by: [asc: d.name])

    render(conn, :index,
      rows: rows,
      totals: totals,
      start_date: start_date,
      end_date: end_date,
      doctor_id: doctor_id,
      rating_filter: rating_filter,
      comments_only: comments_only,
      sort: sort,
      dir: dir,
      doctors: doctors
    )
  end

  defp default_dir("rating"), do: "asc"
  defp default_dir("doctor"), do: "asc"
  defp default_dir(_), do: "desc"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ReviewHTML do
  use LedgrWeb, :html
  embed_templates "review_html/*"

  @doc """
  Renders a 1-5 star rating as filled / empty unicode stars.
  """
  def star_row(n) when is_integer(n) and n >= 0 and n <= 5 do
    String.duplicate("★", n) <> String.duplicate("☆", 5 - n)
  end

  def star_row(_), do: "—"

  @doc "Color for the star row, derived from rating."
  def star_color(n) when n >= 4, do: "#16a34a"
  def star_color(3), do: "#ca8a04"
  def star_color(n) when n in [1, 2], do: "#dc2626"
  def star_color(_), do: "var(--text-muted)"

  @doc """
  Builds a query string for the reviews page with the given overrides
  applied on top of the current filter/sort state. `nil`/`""` values drop the key.
  """
  def reviews_query(assigns, overrides) do
    base = %{
      "start_date" => to_string(assigns.start_date),
      "end_date" => to_string(assigns.end_date),
      "doctor_id" => assigns.doctor_id,
      "rating_filter" => assigns.rating_filter,
      "comments_only" => if(assigns.comments_only, do: "true", else: nil),
      "sort" => assigns.sort,
      "dir" => assigns.dir
    }

    base
    |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
    |> URI.encode_query()
  end

  def sort_arrow(current_sort, current_dir, column) do
    cond do
      to_string(current_sort) != to_string(column) -> ""
      to_string(current_dir) == "asc" -> " ↑"
      true -> " ↓"
    end
  end

  def next_dir(current_sort, current_dir, column) do
    if to_string(current_sort) == to_string(column) do
      if to_string(current_dir) == "asc", do: "desc", else: "asc"
    else
      case to_string(column) do
        "rating" -> "asc"
        "doctor" -> "asc"
        _ -> "desc"
      end
    end
  end
end
