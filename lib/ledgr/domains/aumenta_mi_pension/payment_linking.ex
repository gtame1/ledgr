defmodule Ledgr.Domains.AumentaMiPension.PaymentLinking do
  @moduledoc """
  Links Stripe payments to AMP consultations.

  Two modes:
  - Manual: admin selects a consultation from a dropdown
  - Auto-suggest: finds consultations with pending payment status
  """

  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment
  alias Ledgr.Domains.AumentaMiPension.Consultations.Consultation

  @doc """
  Links a Stripe payment to a consultation. Updates both records.
  """
  def link_payment(payment_id, consultation_id) do
    Repo.transaction(fn ->
      payment = Repo.get!(StripePayment, payment_id)
      consultation = Repo.get!(Consultation, consultation_id)

      {:ok, updated_payment} =
        payment
        |> Ecto.Changeset.change(%{consultation_id: consultation_id})
        |> Repo.update()

      consultation
      |> Ecto.Changeset.change(%{
        payment_status: "paid",
        payment_amount: payment.amount,
        payment_confirmed_at: payment.paid_at,
        stripe_payment_intent_id: payment.stripe_payment_intent_id
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
      case Repo.get(Consultation, payment.consultation_id) do
        nil ->
          :ok

        consultation ->
          consultation
          |> Ecto.Changeset.change(%{
            payment_status: "pending",
            payment_amount: nil,
            payment_confirmed_at: nil,
            stripe_payment_intent_id: nil
          })
          |> Repo.update()
      end
    end

    payment
    |> Ecto.Changeset.change(%{consultation_id: nil})
    |> Repo.update()
  end

  @doc """
  Returns consultations that could match a given payment. Sorted by recency,
  unpaid first.
  """
  def suggest_consultations(%StripePayment{} = _payment) do
    Consultation
    |> where([c], c.payment_status != "paid" or is_nil(c.payment_status))
    |> order_by([c], desc: c.assigned_at)
    |> limit(30)
    |> Repo.all()
    |> Repo.preload([:customer, :agent])
  end

  @doc """
  Returns all unlinked paid payments.
  """
  def unlinked_payments do
    StripePayment
    |> where([p], is_nil(p.consultation_id))
    |> where([p], p.status == "paid")
    |> order_by(desc: :paid_at)
    |> Repo.all()
  end
end
