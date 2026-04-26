defmodule LedgrWeb.Domains.HelloDoctor.PaymentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.StripeSync
  alias Ledgr.Domains.HelloDoctor.StripePayments.StripePayment
  alias Ledgr.Repo

  import Ecto.Query, warn: false

  def index(conn, params) do
    payments =
      StripePayment
      |> order_by(desc: :paid_at)
      |> maybe_filter_status(params["status"])
      |> Repo.all()

    stats = payment_stats()

    render(conn, :index,
      payments: payments,
      stats: stats,
      current_status: params["status"]
    )
  end

  def show(conn, %{"id" => id}) do
    payment = Repo.get!(StripePayment, id)
    render(conn, :show, payment: payment)
  end

  def sync(conn, _params) do
    case StripeSync.sync_recent_payments(limit: 50) do
      {:ok, new_count, existing_count} ->
        msg =
          cond do
            new_count > 0 -> "#{new_count} new payment(s) synced from Stripe."
            existing_count > 0 -> "All #{existing_count} payments already up to date."
            true -> "No HelloDoctor payments found in Stripe."
          end

        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/payments"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Sync failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments"))
    end
  end

  def backfill_gl(conn, _params) do
    {:ok, %{posted: p, skipped: s, errors: e}} = StripeSync.backfill_journal_entries()

    msg   = "GL backfill complete: #{p} posted, #{s} already had entries"
    msg   = if e > 0, do: "#{msg}, #{e} errors (check logs)", else: msg
    flash = if e > 0, do: :error, else: :info

    conn
    |> put_flash(flash, msg <> ".")
    |> redirect(to: dp(conn, "/payments"))
  end

  def link_form(conn, %{"id" => id}) do
    payment = Repo.get!(StripePayment, id)
    suggestions = Ledgr.Domains.HelloDoctor.PaymentLinking.suggest_consultations(payment)

    render(conn, :link_form,
      payment: payment,
      consultations: suggestions
    )
  end

  def save_link(conn, %{"id" => id, "consultation_id" => consultation_id}) do
    case Ledgr.Domains.HelloDoctor.PaymentLinking.link_payment(id, consultation_id) do
      {:ok, _payment} ->
        conn
        |> put_flash(:info, "Payment linked to consultation successfully.")
        |> redirect(to: dp(conn, "/payments/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to link: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments/#{id}/link"))
    end
  end

  def unlink(conn, %{"id" => id}) do
    case Ledgr.Domains.HelloDoctor.PaymentLinking.unlink_payment(id) do
      {:ok, _payment} ->
        conn
        |> put_flash(:info, "Payment unlinked from consultation.")
        |> redirect(to: dp(conn, "/payments/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to unlink: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments/#{id}"))
    end
  end

  def check_status(conn, %{"id" => id}) do
    payment = Repo.get!(StripePayment, id)

    case Ledgr.Domains.HelloDoctor.StripeSync.sync_payment_status(payment) do
      {:ok, :updated, new_status} ->
        conn
        |> put_flash(:info, "Status updated to #{new_status}.")
        |> redirect(to: dp(conn, "/payments/#{id}"))

      {:ok, :unchanged} ->
        conn
        |> put_flash(:info, "Status is already up to date.")
        |> redirect(to: dp(conn, "/payments/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not check status: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments/#{id}"))
    end
  end

  def refund(conn, %{"id" => id}) do
    payment = Repo.get!(StripePayment, id)

    case Ledgr.Domains.HelloDoctor.StripeRefunds.refund_payment(payment) do
      {:ok, updated_payment} ->
        conn
        |> put_flash(:info, "Payment refunded successfully ($#{:erlang.float_to_binary(updated_payment.amount, decimals: 2)} MXN).")
        |> redirect(to: dp(conn, "/payments/#{updated_payment.id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Refund failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments/#{id}"))
    end
  end

  defp payment_stats do
    total_revenue =
      StripePayment
      |> where([p], p.status == "paid")
      |> Repo.aggregate(:sum, :amount) || 0.0

    total_fees =
      StripePayment
      |> where([p], p.status == "paid" and not is_nil(p.stripe_fee))
      |> Repo.aggregate(:sum, :stripe_fee) || 0.0

    total_count =
      StripePayment
      |> where([p], p.status == "paid")
      |> Repo.aggregate(:count)

    commission = total_revenue * 0.15

    %{
      total_revenue: total_revenue,
      total_fees: total_fees,
      total_count: total_count,
      commission: commission
    }
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [p], p.status == ^status)
end

defmodule LedgrWeb.Domains.HelloDoctor.PaymentHTML do
  use LedgrWeb, :html
  embed_templates "payment_html/*"
end
