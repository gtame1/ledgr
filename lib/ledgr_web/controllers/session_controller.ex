defmodule LedgrWeb.SessionController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounts

  def new(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store, no-cache, must-revalidate")
    |> assign(:hide_sidebar, true)
    |> render(:new, error_message: nil)
  end

  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_by_email_and_password(email, password) do
      {:ok, user} ->
        domain = conn.assigns[:current_domain]
        session_key = "user_id:#{domain.slug()}"

        conn
        |> configure_session(renew: true)
        |> put_session(session_key, user.id)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: domain.path_prefix())

      {:error, :invalid_credentials} ->
        conn
        |> assign(:hide_sidebar, true)
        |> render(:new, error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    domain = conn.assigns[:current_domain]
    session_key = "user_id:#{domain.slug()}"

    conn
    |> delete_session(session_key)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: "#{domain.path_prefix()}/login")
  end
end

defmodule LedgrWeb.SessionHTML do
  use LedgrWeb, :html

  embed_templates "session_html/*"
end
