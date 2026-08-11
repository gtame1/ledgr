defmodule Ledgr.Domains.HelloDoctor.LifecycleMetricsTest do
  @moduledoc """
  Pins the test-account filter on the lifecycle base.

  The bug: `WHERE NOT (p.phone IN (...) OR p.id = '...')` is NULL-unsafe.
  `patients.phone` is nullable (dependents created by the bot's dependent
  pivot have none), and for a NULL phone the whole predicate evaluates to
  NULL, so the row was dropped instead of kept — 182 active patients, 7 of
  them holding 8 completed consults, silently missing from the report while
  `patient_segments` retained the same rows.
  """
  use Ledgr.DataCase, async: true

  alias Ledgr.Domains.HelloDoctor.LifecycleMetrics
  alias Ledgr.Domains.HelloDoctor.TestAccounts

  @period_start ~D[2026-01-01]
  @period_end ~D[2026-12-31]
  @first_contact ~N[2026-03-02 12:00:00]

  setup do
    Ledgr.Repo.put_active_repo(Ledgr.Repos.HelloDoctor)
    Ledgr.Domain.put_current(Ledgr.Domains.HelloDoctor)
    :ok
  end

  describe "lifecycle base — test-account filter" do
    test "keeps a patient whose phone IS NULL (the dependent shape)" do
      pid = engaged_patient(phone: nil, is_dependent: true)

      totals = LifecycleMetrics.generate(@period_start, @period_end).totals

      assert totals.leads == 1, "NULL-phone patient was dropped from the lifecycle base"
      assert totals.converted == 1
      assert totals.l2 == 1
      assert pid != nil
    end

    test "still excludes a patient on a known test phone" do
      engaged_patient(phone: hd(TestAccounts.test_phones()))

      totals = LifecycleMetrics.generate(@period_start, @period_end).totals

      assert totals.leads == 0
      assert totals.converted == 0
    end

    test "still excludes the legacy test patient id" do
      engaged_patient(id: hd(TestAccounts.test_patient_ids()), phone: "5215599990001")

      totals = LifecycleMetrics.generate(@period_start, @period_end).totals

      assert totals.leads == 0
    end

    test "keeps an ordinary patient alongside a NULL-phone one" do
      engaged_patient(phone: nil, is_dependent: true)
      engaged_patient(phone: "5215599990002")

      totals = LifecycleMetrics.generate(@period_start, @period_end).totals

      assert totals.leads == 2
      assert totals.converted == 2
    end
  end

  # ── fixtures ──────────────────────────────────────────────────────
  # Raw SQL: `patients` / `conversations` / `messages` / `consultations`
  # are bot-owned, so Ledgr has no writable Ecto schema for them.

  # An L2 patient: 3 inbound messages (engaged) + 1 completed, charged consult.
  defp engaged_patient(opts) do
    pid = Keyword.get_lazy(opts, :id, &Ecto.UUID.generate/0)
    conv_id = Ecto.UUID.generate()

    sql!(
      """
      INSERT INTO patients (id, phone, full_name, is_dependent, created_at, updated_at)
      VALUES ($1, $2, 'Fixture', $3, $4, $4)
      """,
      [pid, Keyword.get(opts, :phone), Keyword.get(opts, :is_dependent, false), @first_contact]
    )

    sql!(
      """
      INSERT INTO conversations
        (id, patient_id, status, funnel_stage, doctor_recommended,
         doctor_declined_by_patient, created_at, last_message_at, payment_source)
      VALUES ($1, $2, 'closed', 'data_collected', false, false, $3, $3, 'stripe')
      """,
      [conv_id, pid, @first_contact]
    )

    for _ <- 1..3 do
      sql!(
        """
        INSERT INTO messages (id, conversation_id, role, content, message_type, created_at)
        VALUES ($1, $2, 'user', 'hola', 'text', $3)
        """,
        [Ecto.UUID.generate(), conv_id, @first_contact]
      )
    end

    sql!(
      """
      INSERT INTO consultations
        (id, conversation_id, patient_id, status, assigned_at, completed_at,
         payment_status, payment_amount, payment_source)
      VALUES ($1, $2, $3, 'completed', $4, $4, 'paid', 135.0, 'stripe')
      """,
      [Ecto.UUID.generate(), conv_id, pid, @first_contact]
    )

    pid
  end

  defp sql!(sql, params),
    do: Ecto.Adapters.SQL.query!(Ledgr.Repos.HelloDoctor, sql, params)
end
