defmodule LedgrWeb.Domains.AumentaMiPension.PaymentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment
  alias Ledgr.Repo

  import Ecto.Query, warn: false

  @not_configured_msg "Stripe no está configurado para este dominio todavía"

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
    if Ledgr.Domains.AumentaMiPension.stripe_configured?() do
      conn
      |> put_flash(:error, "Sincronización de Stripe aún no implementada para este dominio.")
      |> redirect(to: dp(conn, "/payments"))
    else
      conn
      |> put_flash(:error, @not_configured_msg)
      |> redirect(to: dp(conn, "/payments"))
    end
  end

  def link_form(conn, %{"id" => id}) do
    payment = Repo.get!(StripePayment, id)

    render(conn, :link_form,
      payment: payment,
      consultations: []
    )
  end

  def save_link(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, @not_configured_msg)
    |> redirect(to: dp(conn, "/payments/#{id}/link"))
  end

  def unlink(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, @not_configured_msg)
    |> redirect(to: dp(conn, "/payments/#{id}"))
  end

  def check_status(conn, %{"id" => id}) do
    if Ledgr.Domains.AumentaMiPension.stripe_configured?() do
      conn
      |> put_flash(:error, "Verificación de estatus aún no implementada para este dominio.")
      |> redirect(to: dp(conn, "/payments/#{id}"))
    else
      conn
      |> put_flash(:error, @not_configured_msg)
      |> redirect(to: dp(conn, "/payments/#{id}"))
    end
  end

  def refund(conn, %{"id" => id}) do
    if Ledgr.Domains.AumentaMiPension.stripe_configured?() do
      conn
      |> put_flash(:error, "Reembolsos aún no implementados para este dominio.")
      |> redirect(to: dp(conn, "/payments/#{id}"))
    else
      conn
      |> put_flash(:error, @not_configured_msg)
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

defmodule LedgrWeb.Domains.AumentaMiPension.PaymentHTML do
  use LedgrWeb, :html
  embed_templates "payment_html/*"
end
