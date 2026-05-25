defmodule Ledgr.Domains.HelloDoctor.Reviews do
  @moduledoc """
  Patient feedback on completed consultations — rating (1-5) and free-text
  comment, both written by the patient via the WhatsApp bot after the
  consultation ends.

  Surface for the Reviews page. The page lists individual reviews so
  operators can read qualitative feedback and spot bad ratings; per-doctor
  stats are derived from the same rows in `summarize/1`.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Patients.Patient

  @doc """
  Returns rated consultations in [start_date, end_date], joined with
  doctor + patient, ordered by completed_at desc.

  ## Options

    * `:doctor_id` — restrict to one doctor (`nil` / `""` / `"all"` = all)
    * `:rating_filter` — one of:
        * `nil` / `""` / `"all"` — no rating filter
        * `"5"` — exactly 5★
        * `"4"` — 4★ and above
        * `"3"` — 3★ and above
        * `"low"` — 2★ and below (the ones worth flagging)
    * `:comments_only` — when true, only rows with a non-empty comment
    * `:sort` — `:date` (default), `:rating`, `:doctor`
    * `:dir` — `:asc` / `:desc`. Defaults: date→desc, rating→asc (worst first), doctor→asc.

  Each row map:
    * `:consultation_id`, `:completed_at`, `:completed_date`
    * `:doctor_id`, `:doctor_name`, `:doctor_specialty`
    * `:patient_name`
    * `:rating` (integer 1-5)
    * `:comment` (string, may be nil/empty)
  """
  def list_reviews(start_date, end_date, opts \\ []) do
    start_naive = NaiveDateTime.new!(start_date, ~T[00:00:00])
    end_naive = NaiveDateTime.new!(end_date, ~T[23:59:59])

    base =
      from c in Consultation,
        left_join: d in Doctor,
        on: d.id == c.doctor_id,
        left_join: pt in Patient,
        on: pt.id == c.patient_id,
        where: not is_nil(c.patient_rating),
        where: c.completed_at >= ^start_naive and c.completed_at <= ^end_naive,
        select: %{
          consultation_id: c.id,
          completed_at: c.completed_at,
          doctor_id: d.id,
          doctor_name: d.name,
          doctor_specialty: d.specialty,
          patient_full_name: pt.full_name,
          patient_display_name: pt.display_name,
          rating: c.patient_rating,
          comment: c.patient_comment
        }

    base
    |> filter_doctor(opts[:doctor_id])
    |> filter_rating(opts[:rating_filter])
    |> filter_comments_only(opts[:comments_only])
    |> Repo.all()
    |> Enum.map(&shape_row/1)
    |> apply_sort(opts[:sort], opts[:dir])
  end

  defp filter_doctor(query, id) when id in [nil, "", "all"], do: query
  defp filter_doctor(query, id), do: from([c, _d, _pt] in query, where: c.doctor_id == ^id)

  defp filter_rating(query, val) when val in [nil, "", "all"], do: query

  defp filter_rating(query, "5"),
    do: from([c, _d, _pt] in query, where: c.patient_rating == 5)

  defp filter_rating(query, "4"),
    do: from([c, _d, _pt] in query, where: c.patient_rating >= 4)

  defp filter_rating(query, "3"),
    do: from([c, _d, _pt] in query, where: c.patient_rating >= 3)

  defp filter_rating(query, "low"),
    do: from([c, _d, _pt] in query, where: c.patient_rating <= 2)

  defp filter_rating(query, _), do: query

  defp filter_comments_only(query, true) do
    from([c, _d, _pt] in query,
      where: not is_nil(c.patient_comment) and c.patient_comment != ""
    )
  end

  defp filter_comments_only(query, "true") do
    filter_comments_only(query, true)
  end

  defp filter_comments_only(query, _), do: query

  defp shape_row(row) do
    %{
      consultation_id: row.consultation_id,
      completed_at: row.completed_at,
      completed_date: completed_date(row.completed_at),
      doctor_id: row.doctor_id,
      doctor_name: row.doctor_name || "Unassigned",
      doctor_specialty: row.doctor_specialty,
      patient_name: row.patient_full_name || row.patient_display_name || "Unknown",
      rating: row.rating,
      comment: (row.comment || "") |> String.trim()
    }
  end

  defp completed_date(nil), do: nil
  defp completed_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)

  # ── Sorting ─────────────────────────────────────────────────────

  defp apply_sort(rows, sort, dir) do
    sort = normalize_sort(sort)
    dir = normalize_dir(dir, sort)
    Enum.sort_by(rows, sort_key(sort), sort_comparer(dir))
  end

  defp normalize_sort(s) when s in [nil, "", :date, "date"], do: :date
  defp normalize_sort(s) when s in [:rating, "rating"], do: :rating
  defp normalize_sort(s) when s in [:doctor, "doctor"], do: :doctor
  defp normalize_sort(_), do: :date

  defp normalize_dir(d, _) when d in [:asc, "asc"], do: :asc
  defp normalize_dir(d, _) when d in [:desc, "desc"], do: :desc
  defp normalize_dir(_, :rating), do: :asc
  defp normalize_dir(_, :doctor), do: :asc
  defp normalize_dir(_, _), do: :desc

  defp sort_key(:date), do: &(&1.completed_at || ~N[1970-01-01 00:00:00])
  defp sort_key(:rating), do: & &1.rating
  defp sort_key(:doctor), do: & &1.doctor_name

  defp sort_comparer(:asc), do: &<=/2
  defp sort_comparer(:desc), do: &>=/2

  # ── KPI summary ─────────────────────────────────────────────────

  @doc """
  Aggregates a list of review rows (as returned by `list_reviews/3`) into
  totals for the page header.

  Returns `%{count, avg_rating, with_comment, by_rating}` where `:by_rating`
  is a map of `1..5 => count`.
  """
  def summarize(rows) do
    count = length(rows)

    by_rating =
      Enum.reduce(1..5, %{}, fn r, acc -> Map.put(acc, r, 0) end)
      |> then(fn base ->
        Enum.reduce(rows, base, fn row, acc ->
          Map.update(acc, row.rating, 1, &(&1 + 1))
        end)
      end)

    with_comment = Enum.count(rows, &(&1.comment != ""))

    avg_rating =
      if count > 0 do
        rows |> Enum.map(& &1.rating) |> Enum.sum() |> Kernel./(count) |> Float.round(2)
      else
        nil
      end

    %{
      count: count,
      avg_rating: avg_rating,
      with_comment: with_comment,
      by_rating: by_rating
    }
  end
end
