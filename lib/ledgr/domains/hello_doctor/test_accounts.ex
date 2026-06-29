defmodule Ledgr.Domains.HelloDoctor.TestAccounts do
  @moduledoc """
  Single source of truth for HelloDoctor's internal test identities.

  Two distinct mechanisms, each used where it makes sense:

    * **Test phones** — numbers the team uses for QA/demos. Reports flag or
      filter conversations/patients by these.
    * **Test patient ids** — the legacy `/prueba` test patient, excluded
      from lifecycle tiers.

  Centralized here so the lists don't drift across the various reports that
  reference them. `*_sql/0` return ready-to-interpolate SQL literal lists —
  these are compile-time constants, not user input, so interpolation is safe.
  """

  @test_phones ~w(5215512950400 5215543408539 5215536713304)
  @test_patient_ids ~w(2ed77952-cead-4bc4-bc44-51f5b5052d76)

  @doc "Known internal test phone numbers (normalized, no +)."
  def test_phones, do: @test_phones

  @doc "Known internal test patient ids."
  def test_patient_ids, do: @test_patient_ids

  @doc "Test phones as a SQL literal list for an `IN (...)` clause."
  def phones_sql, do: sql_list(@test_phones)

  @doc "Test patient ids as a SQL literal list for an `IN (...)` clause."
  def patient_ids_sql, do: sql_list(@test_patient_ids)

  @doc """
  A SQL `EXISTS (...)` predicate, true when the patient referenced by
  `patient_id_expr` IS a test account (test phone OR test patient id).

  `patient_id_expr` is a SQL expression for the patient id column in scope,
  e.g. `"c.patient_id"`, `"p.id"`, `"ps.patient_id"`.
  """
  def is_test_patient_sql(patient_id_expr) do
    """
    EXISTS (
      SELECT 1 FROM patients tp
      WHERE tp.id = #{patient_id_expr}
        AND (tp.phone IN (#{phones_sql()}) OR tp.id IN (#{patient_ids_sql()}))
    )
    """
  end

  @doc """
  Negation of `is_test_patient_sql/1` — true when the patient is NOT a test
  account. Drop into a WHERE/AND to exclude test patients uniformly. Uses
  `NOT EXISTS`, so a NULL patient id passes (it isn't a test patient) — note
  `patient_id NOT IN (...)` would wrongly drop NULLs.
  """
  def not_test_patient_sql(patient_id_expr), do: "NOT " <> is_test_patient_sql(patient_id_expr)

  defp sql_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
