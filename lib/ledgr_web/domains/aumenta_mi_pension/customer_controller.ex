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
    preview = lookup_preview(conn, id)
    blocked = lookup_blocked(conn, id)

    render(conn, :show, customer: customer, preview: preview, blocked: blocked)
  end

  # `discard_preview` clears the stashed preview without doing anything else.
  # Phone confirmation isn't required because nothing destructive happens.
  def reset(conn, %{"id" => id, "action" => "discard_preview"}) do
    conn
    |> clear_preview()
    |> put_flash(:info, "Preview discarded.")
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  # `dismiss_blocked` clears the "blocked by pending obligations" card.
  def reset(conn, %{"id" => id, "action" => "dismiss_blocked"}) do
    conn
    |> clear_blocked()
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  # `execute_preview` re-uses force/reason from the stashed preview so the
  # admin doesn't have to re-type. Still gated by JS confirm() in the
  # template; the existence of a fresh preview is the human-confirmation step.
  def reset(conn, %{"id" => id, "action" => "execute_preview"}) do
    customer = Customers.get_customer!(id)

    case lookup_preview(conn, id) do
      nil ->
        conn
        |> put_flash(:error, "No preview to execute. Run preview first.")
        |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")

      preview ->
        opts = [
          force: preview["force"] || false,
          reason: "#{preview["reason"] || "ledgr admin"} (via Ledgr, confirmed preview)"
        ]

        result = CustomerReset.execute(customer.phone, opts)

        conn
        |> clear_preview()
        |> handle_result(id, "execute", preview["force"] || false, result)
    end
  end

  def reset(conn, %{"id" => id, "confirm_phone" => phone, "action" => action} = params) do
    customer = Customers.get_customer!(id)

    cond do
      to_string(phone) != to_string(customer.phone) ->
        conn
        |> put_flash(:error, "Phone number doesn't match. Action cancelled.")
        |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")

      action not in ~w[preview execute] ->
        conn
        |> put_flash(:error, "Invalid action.")
        |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")

      true ->
        force? = params["force"] == "on"
        reason = params["reason"] || "ledgr admin"

        opts = [force: force?, reason: "#{reason} (via Ledgr)"]

        case action do
          "preview" ->
            case CustomerReset.preview(customer.phone, opts) do
              {:ok, body} ->
                preview_data = %{
                  "body" => body,
                  "force" => force?,
                  "reason" => reason,
                  "customer_id" => id,
                  "previewed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                }

                conn
                |> stash_preview(preview_data)
                |> clear_blocked()
                |> put_flash(:info, "Preview ready — see the card above the form.")
                |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")

              other ->
                handle_result(conn, id, "preview", force?, other)
            end

          "execute" ->
            result = CustomerReset.execute(customer.phone, opts)

            conn
            |> clear_preview()
            |> clear_blocked()
            |> handle_result(id, "execute", force?, result)
        end
    end
  end

  def reset(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Missing parameters. Confirm phone and select an action.")
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  # ── Result handling ──────────────────────────────────────────────────

  defp handle_result(conn, id, "preview", _force?, {:ok, body}) do
    conn
    |> put_flash(:info, "Reset preview: " <> summarize(body))
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp handle_result(conn, id, "execute", _force?, {:ok, body}) do
    conn
    |> put_flash(:info, "Customer reset. " <> summarize(body))
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp handle_result(conn, id, action, _force?, {:error, {:unfulfilled_payments, pending}}) do
    blocked_data = %{
      "customer_id" => id,
      "attempted_action" => action,
      "pending" => pending,
      "blocked_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn
    |> stash_blocked(blocked_data)
    |> put_flash(
      :error,
      "Reset blocked by unfulfilled payments — see the card above the form."
    )
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp handle_result(conn, id, _action, _force?, {:error, {:not_configured, what}}) do
    conn
    |> put_flash(
      :error,
      "Bot service not configured (#{what}). Set AUMENTA_MI_PENSION_BOT_URL and AUMENTA_MI_PENSION_BOT_ADMIN_API_KEY, then restart the server."
    )
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp handle_result(conn, id, _action, _force?, {:error, {:http_error, status, body}}) do
    conn
    |> put_flash(:error, "Bot returned HTTP #{status}: #{inspect(body)}")
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp handle_result(conn, id, _action, _force?, {:error, reason}) do
    conn
    |> put_flash(:error, "Bot communication error: #{inspect(reason)}")
    |> redirect(to: dp(conn, "/customers/#{id}") <> "#reset-section")
  end

  defp summarize(body) when is_map(body) do
    parts = [
      counter(body, "conversations_closed", "conversations closed"),
      counter(body, "messages_orphaned", "messages orphaned"),
      counter(body, "pension_cases_deleted", "pension cases deleted"),
      counter(body, "consultations_preserved", "consultations preserved"),
      counter(body, "payments_preserved", "payments preserved"),
      fields_nulled(body),
      counter(body, "stripe_payments_unlinked", "Ledgr payments unlinked"),
      forced_note(body)
    ]

    parts
    |> Enum.reject(&(&1 == nil))
    |> Enum.join(", ")
  end

  defp counter(body, key, label) do
    case Map.get(body, key) do
      nil -> nil
      0 -> nil
      n -> "#{label}: #{n}"
    end
  end

  defp fields_nulled(%{"fields_nulled" => fields}) when is_list(fields) and fields != [] do
    "onboarding fields cleared: #{length(fields)}"
  end

  defp fields_nulled(_), do: nil

  defp forced_note(%{"forced" => true, "pending_obligations" => pending}) when pending != [] do
    "FORCED past #{length(pending)} pending obligation(s)"
  end

  defp forced_note(_), do: nil

  # ── Preview session stash ────────────────────────────────────────────

  @preview_session_key :amp_reset_preview

  defp stash_preview(conn, preview_data) do
    Plug.Conn.put_session(conn, @preview_session_key, preview_data)
  end

  defp clear_preview(conn) do
    Plug.Conn.delete_session(conn, @preview_session_key)
  end

  defp lookup_preview(conn, customer_id) do
    case Plug.Conn.get_session(conn, @preview_session_key) do
      %{"customer_id" => ^customer_id} = preview -> preview
      _ -> nil
    end
  end

  @blocked_session_key :amp_reset_blocked

  defp stash_blocked(conn, blocked_data) do
    Plug.Conn.put_session(conn, @blocked_session_key, blocked_data)
  end

  defp clear_blocked(conn) do
    Plug.Conn.delete_session(conn, @blocked_session_key)
  end

  defp lookup_blocked(conn, customer_id) do
    case Plug.Conn.get_session(conn, @blocked_session_key) do
      %{"customer_id" => ^customer_id} = blocked -> blocked
      _ -> nil
    end
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.CustomerHTML do
  use LedgrWeb, :html
  embed_templates "customer_html/*"
end
