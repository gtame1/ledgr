defmodule LedgrWeb.Plugs.AuthPlug do
  @moduledoc """
  Plug that checks for an authenticated user in the session.

  Must run AFTER DomainPlug since it needs the domain context
  to determine which session key to check.

  Session keys are domain-scoped: "user_id:mr-munch-me", "user_id:viaxe"
  to prevent cross-domain session bleed.
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    domain = conn.assigns[:current_domain]

    if domain do
      session_key = "user_id:#{domain.slug()}"
      user_id = get_session(conn, session_key)

      Logger.debug(
        "[AuthPlug] domain=#{domain.slug()} session_key=#{session_key} user_id=#{inspect(user_id)}"
      )

      if user_id do
        user = Ledgr.Repo.get(Ledgr.Core.Accounts.User, user_id)

        if user do
          Logger.debug("[AuthPlug] authenticated user=#{user.email}")
          assign(conn, :current_user, user)
        else
          # Stale session — user was deleted
          Logger.warning("[AuthPlug] stale session for user_id=#{user_id}, redirecting to login")

          conn
          |> clear_session()
          |> redirect(to: "#{domain.path_prefix()}/login")
          |> halt()
        end
      else
        Logger.warning("[AuthPlug] no session for domain=#{domain.slug()}, redirecting to login")

        conn
        |> redirect(to: "#{domain.path_prefix()}/login")
        |> halt()
      end
    else
      # No domain context (landing page) — skip auth
      conn
    end
  end
end
