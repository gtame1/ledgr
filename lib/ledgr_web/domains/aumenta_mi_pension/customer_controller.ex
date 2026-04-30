defmodule LedgrWeb.Domains.AumentaMiPension.CustomerController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Customers
  alias Ledgr.Domains.AumentaMiPension.CustomerReset

  def index(conn, params) do
    customers = Customers.list_customers(search: params["search"])

    render(conn, :index,
      customers: customers,
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    customer = Customers.get_customer!(id)

    render(conn, :show, customer: customer)
  end

  def reset(conn, %{"id" => id, "confirm_phone" => phone, "level" => level_str}) do
    customer = Customers.get_customer!(id)

    cond do
      to_string(phone) != to_string(customer.phone) ->
        conn
        |> put_flash(:error, "El número de teléfono no coincide. Reinicio cancelado.")
        |> redirect(to: dp(conn, "/customers/#{id}"))

      level_str not in ~w[conversation onboarding] ->
        conn
        |> put_flash(:error, "Nivel de reinicio inválido.")
        |> redirect(to: dp(conn, "/customers/#{id}"))

      true ->
        level = String.to_existing_atom(level_str)

        case CustomerReset.reset(id, level) do
          {:ok, c} ->
            level_label =
              case level do
                :conversation -> "conversación"
                :onboarding -> "onboarding completo"
              end

            paid_note =
              if c.conversations_kept_paid > 0 do
                " #{c.conversations_kept_paid} conversación(es) con pagos preservada(s) (#{c.payments_preserved} pago(s))."
              else
                ""
              end

            conn
            |> put_flash(
              :info,
              "Cliente reiniciado (#{level_label}). Conversaciones eliminadas: #{c.conversations_deleted}/#{c.conversations_total}, mensajes: #{c.messages}, consultas: #{c.consultations}, pension cases: #{c.pension_cases}, outbound: #{c.outbound_messages}, llamadas: #{c.consultation_calls}, pagos Ledgr desvinculados: #{c.stripe_payments_unlinked}.#{paid_note}"
            )
            |> redirect(to: dp(conn, "/customers/#{id}"))

          {:error, reason} ->
            conn
            |> put_flash(:error, "Error al reiniciar: #{inspect(reason)}")
            |> redirect(to: dp(conn, "/customers/#{id}"))
        end
    end
  end

  def reset(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Faltan parámetros. Confirma el teléfono y selecciona un nivel.")
    |> redirect(to: dp(conn, "/customers/#{id}"))
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.CustomerHTML do
  use LedgrWeb, :html
  embed_templates "customer_html/*"
end
