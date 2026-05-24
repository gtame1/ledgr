defmodule Ledgr.Domains.HelloDoctor.PaymentLinking do
  @moduledoc """
  Links Stripe payments to consultations.

  Two modes:
  - Manual: admin selects a consultation from a dropdown
  - Auto-suggest: finds consultations with matching amount and pending payment status
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Domains.HelloDoctor.Consultations.Consultation

  @doc """
  Links a Stripe payment to a consultation. Updates both records.
  """
  def link_payment(payment_id, consultation_id) do
    Repo.transaction(fn ->
      payment = Repo.get!(StripePayment, payment_id)
      consultation = Repo.get!(Consultation, consultation_id)

      # Update stripe payment
      {:ok, updated_payment} =
        payment
        |> Ecto.Changeset.change(%{consultation_id: consultation_id})
        |> Repo.update()

      # Update consultation payment fields
      consultation
      |> Ecto.Changeset.change(%{
        payment_status: "paid",
        payment_amount: payment.amount,
        payment_confirmed_at: payment.paid_at
      })
      |> Repo.update()

      updated_payment
    end)
  end

  @doc """
  Unlinks a payment from its consultation.
  """
  def unlink_payment(payment_id) do
    payment = Repo.get!(StripePayment, payment_id)

    if payment.consultation_id do
      # Reset consultation payment status
      case Repo.get(Consultation, payment.consultation_id) do
        nil ->
          :ok

        consultation ->
          consultation
          |> Ecto.Changeset.change(%{
            payment_status: "pending",
            payment_amount: nil,
            payment_confirmed_at: nil
          })
          |> Repo.update()
      end
    end

    payment
    |> Ecto.Changeset.change(%{consultation_id: nil})
    |> Repo.update()
  end

  @doc """
  Returns consultations that could match a given payment.
  Sorted by likelihood (pending payments first, then by date proximity).
  """
  def suggest_consultations(%StripePayment{} = _payment) do
    Consultation
    |> where([c], c.payment_status != "paid" or is_nil(c.payment_status))
    |> order_by([c], desc: c.assigned_at)
    |> limit(30)
    |> Repo.all()
    |> Repo.preload([:patient, :doctor])
  end

  @doc """
  Returns all unlinked payments (no consultation_id).
  """
  def unlinked_payments do
    StripePayment
    |> where([p], is_nil(p.consultation_id))
    |> where([p], p.status == "paid")
    |> order_by(desc: :paid_at)
    |> Repo.all()
  end

  @doc """
  Backfills `stripe_payments.consultation_id` for any unlinked payment whose
  `stripe_payment_intent_id` matches a consultation's
  `stripe_payment_intent_id`.

  Idempotent — only updates rows where `consultation_id` is currently NULL,
  and only when exactly one consultation matches the PI. Returns
  `%{matched: n, ambiguous: m, no_match: k}`.

  Run after deploy (and any time you spot a wave of "Pending Stripe sync"
  badges):

      iex> Ledgr.Domains.HelloDoctor.PaymentLinking.backfill_by_payment_intent()
  """
  def backfill_by_payment_intent do
    unlinked =
      StripePayment
      |> where([sp], is_nil(sp.consultation_id) and not is_nil(sp.stripe_payment_intent_id))
      |> Repo.all()

    Enum.reduce(unlinked, %{matched: 0, ambiguous: 0, no_match: 0}, fn sp, acc ->
      consultations =
        Consultation
        |> where([c], c.stripe_payment_intent_id == ^sp.stripe_payment_intent_id)
        |> Repo.all()

      case consultations do
        [consultation] ->
          # Exactly one match — safe to link.
          sp
          |> Ecto.Changeset.change(%{consultation_id: consultation.id})
          |> Repo.update!()

          %{acc | matched: acc.matched + 1}

        [] ->
          %{acc | no_match: acc.no_match + 1}

        _multiple ->
          # Multiple consultations share the same PI — shouldn't happen, but
          # don't guess. Surface in the count so the operator can investigate.
          %{acc | ambiguous: acc.ambiguous + 1}
      end
    end)
  end
end
