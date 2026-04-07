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
      {:ok, count} ->
        conn
        |> put_flash(:info, "Synced #{count} payments from Stripe.")
        |> redirect(to: dp(conn, "/payments"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Sync failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/payments"))
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
