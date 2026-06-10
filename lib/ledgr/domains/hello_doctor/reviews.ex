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

  Each row map carries all four rating dimensions and both comments:
    * `:consultation_id`, `:completed_at`, `:completed_date`
    * `:doctor_id`, `:doctor_name`, `:doctor_specialty`, `:patient_name`
    * `:doctor_rating` — patient rated the doctor (1-5, may be nil)
    * `:patient_platform_rating` — patient rated the platform (may be nil)
    * `:patient_rating_by_doctor` — doctor rated the patient (may be nil)
    * `:doctor_platform_rating` — doctor rated the platform (may be nil)
    * `:patient_comment`, `:doctor_comment` (strings, may be empty)
    * `:rating` — convenience alias for `doctor_rating` (used by sort/filter
       semantics that target "patient feedback about the doctor")
  """
  def list_reviews(start_date, end_date, opts \\ []) do
    # Bounds are Mexico City wall-clock; `completed_at` is UTC-stored.
    # See Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive/1.
    start_naive = Ledgr.Domains.HelloDoctor.mx_day_start_utc_naive(start_date)
    end_exclusive = Ledgr.Domains.HelloDoctor.mx_day_end_utc_naive(end_date)

    base =
      from c in Consultation,
        left_join: d in Doctor,
        on: d.id == c.doctor_id,
        left_join: pt in Patient,
        on: pt.id == c.patient_id,
        # Show rows where ANY of the four ratings is filled — doctor-side
        # feedback shouldn't disappear just because the patient skipped.
        where:
          not is_nil(c.patient_rating) or
            not is_nil(c.patient_platform_rating) or
            not is_nil(c.doctor_rating) or
            not is_nil(c.doctor_platform_rating),
        where: c.completed_at >= ^start_naive and c.completed_at < ^end_exclusive,
        select: %{
          consultation_id: c.id,
          completed_at: c.completed_at,
          doctor_id: d.id,
          doctor_name: d.name,
          doctor_specialty: d.specialty,
          patient_full_name: pt.full_name,
          patient_display_name: pt.display_name,
          doctor_rating: c.patient_rating,
          patient_platform_rating: c.patient_platform_rating,
          patient_rating_by_doctor: c.doctor_rating,
          doctor_platform_rating: c.doctor_platform_rating,
          patient_comment: c.patient_comment,
          doctor_comment: c.doctor_comment
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
      where:
        (not is_nil(c.patient_comment) and c.patient_comment != "") or
          (not is_nil(c.doctor_comment) and c.doctor_comment != "")
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
      doctor_rating: row.doctor_rating,
      patient_platform_rating: row.patient_platform_rating,
      patient_rating_by_doctor: row.patient_rating_by_doctor,
      doctor_platform_rating: row.doctor_platform_rating,
      patient_comment: (row.patient_comment || "") |> String.trim(),
      doctor_comment: (row.doctor_comment || "") |> String.trim(),
      # Convenience alias — `:rating` is used by sort/filter logic that
      # targets the headline "patient → doctor" score.
      rating: row.doctor_rating
    }
  end

  defp completed_date(nil), do: nil
  defp completed_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)

  # ── Sorting ─────────────────────────────────────────────────────

  # Important: Erlang term ordering compares structs field-by-field in
  # ALPHABETICAL key order, not by semantic meaning. For NaiveDateTime
  # the fields land in the order calendar / day / hour / microsecond /
  # minute / month / second / year — so `~N[2026-05-29] >= ~N[2026-06-10]`
  # evaluates true (day 29 > day 10 before month is even checked).
  # `Enum.sort_by/3` with `{:desc, NaiveDateTime}` dispatches through
  # `NaiveDateTime.compare/2` which is correct.
  defp apply_sort(rows, sort, dir) do
    sort = normalize_sort(sort)
    dir = normalize_dir(dir, sort)

    case sort do
      :date ->
        Enum.sort_by(rows, & &1.completed_at, {dir, NaiveDateTime})

      :rating ->
        # nil ratings sort below 0 so they pin to the bottom regardless of
        # direction.
        Enum.sort_by(rows, &(&1.rating || -1), dir)

      :doctor ->
        Enum.sort_by(rows, & &1.doctor_name, dir)
    end
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

  # ── KPI summary ─────────────────────────────────────────────────

  @doc """
  Aggregates a list of review rows (as returned by `list_reviews/3`) into
  totals for the page header.

  Returns a map with:
    * `:count` — number of rows in the period
    * `:avg_doctor_rating` — avg patient → doctor (the headline)
    * `:avg_patient_platform_rating` — avg patient → platform
    * `:avg_patient_rating_by_doctor` — avg doctor → patient
    * `:avg_doctor_platform_rating` — avg doctor → platform
    * `:avg_rating` — alias for `:avg_doctor_rating` (back-compat)
    * `:with_comment` — count of rows with either a patient or doctor comment
    * `:by_rating` — map `1..5 => count` for the headline doctor rating
  """
  def summarize(rows) do
    count = length(rows)

    by_rating =
      Enum.reduce(1..5, %{}, fn r, acc -> Map.put(acc, r, 0) end)
      |> then(fn base ->
        Enum.reduce(rows, base, fn row, acc ->
          if row.doctor_rating, do: Map.update(acc, row.doctor_rating, 1, &(&1 + 1)), else: acc
        end)
      end)

    with_comment =
      Enum.count(rows, &(&1.patient_comment != "" or &1.doctor_comment != ""))

    avg_doctor_rating = average_of(rows, & &1.doctor_rating)
    avg_patient_platform_rating = average_of(rows, & &1.patient_platform_rating)
    avg_patient_rating_by_doctor = average_of(rows, & &1.patient_rating_by_doctor)
    avg_doctor_platform_rating = average_of(rows, & &1.doctor_platform_rating)

    %{
      count: count,
      avg_doctor_rating: avg_doctor_rating,
      avg_patient_platform_rating: avg_patient_platform_rating,
      avg_patient_rating_by_doctor: avg_patient_rating_by_doctor,
      avg_doctor_platform_rating: avg_doctor_platform_rating,
      # Back-compat alias for callers that still expect a single number.
      avg_rating: avg_doctor_rating,
      with_comment: with_comment,
      by_rating: by_rating
    }
  end

  defp average_of(rows, getter) do
    values = rows |> Enum.map(getter) |> Enum.reject(&is_nil/1)

    case values do
      [] -> nil
      _ -> values |> Enum.sum() |> Kernel./(length(values)) |> Float.round(2)
    end
  end
end
