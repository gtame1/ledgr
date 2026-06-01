defmodule Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions do
  @moduledoc """
  Override layer that controls whether a consultation produces a
  doctor payable. Single source of truth — both the Doctor Payouts
  page and the Monthly Report consult this table.

  The default is **always "pay the doctor"** — i.e., a consultation
  without a row here is treated as `pay_doctor = true`. Rows only
  exist when an operator (or the system, on refund) explicitly
  recorded a non-default decision.

  Lives in the HelloDoctor (Ledgr-owned) Postgres alongside other
  Ledgr tables; the `consultation_id` references the bot-owned
  `consultations` table by id but is not a hard FK (the bot writes
  consultations on a schedule we don't control).
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions.Decision

  @doc """
  Returns the decision row for a consultation, or `nil` if none exists.
  """
  def get(consultation_id) when is_binary(consultation_id) do
    Repo.get_by(Decision, consultation_id: consultation_id)
  end

  def get(_), do: nil

  @doc """
  Returns the effective pay-doctor decision for a consultation.
  Defaults to `true` when no row exists.
  """
  def pay_doctor?(consultation_id) do
    case get(consultation_id) do
      nil -> true
      %Decision{pay_doctor: v} -> v
    end
  end

  @doc """
  Batch lookup of pay-doctor decisions for a list of consultation IDs.
  Returns a map `%{consultation_id => pay_doctor_bool}`. Consultations
  without a row are simply absent from the map — caller should default
  to `true`.

  Useful when joining a list of consultations to their decisions
  without an N+1 query.
  """
  def pay_doctor_map(consultation_ids) when is_list(consultation_ids) do
    ids = Enum.reject(consultation_ids, &is_nil/1)

    if ids == [] do
      %{}
    else
      from(d in Decision,
        where: d.consultation_id in ^ids,
        select: {d.consultation_id, d.pay_doctor}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  @doc """
  Inserts or updates a decision for a consultation.

  Required:
    * `consultation_id`
    * `pay_doctor`

  Optional opts:
    * `:reason` — free text, retained for audit
    * `:decided_by` — operator email or `"system"`
  """
  def upsert(consultation_id, pay_doctor, opts \\ [])
      when is_binary(consultation_id) and is_boolean(pay_doctor) do
    attrs = %{
      consultation_id: consultation_id,
      pay_doctor: pay_doctor,
      reason: Keyword.get(opts, :reason),
      decided_by: Keyword.get(opts, :decided_by, "system")
    }

    case get(consultation_id) do
      nil -> %Decision{} |> Decision.changeset(attrs) |> Repo.insert()
      existing -> existing |> Decision.changeset(attrs) |> Repo.update()
    end
  end
end
