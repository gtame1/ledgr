defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_domain] do
      nil ->
        redirect(conn, to: "/mr-munch-me/menu")

      domain ->
        redirect(conn, to: "#{domain.path_prefix()}/login")
    end
  end
end
