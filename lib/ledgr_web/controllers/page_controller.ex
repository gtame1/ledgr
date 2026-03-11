defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    case conn.assigns[:current_domain] do
      nil ->
        domains =
          Application.get_env(:ledgr, :domains, [])
          |> Enum.map(fn mod ->
            %{
              name: mod.name(),
              logo: mod.logo(),
              path: "#{mod.path_prefix()}/login",
              theme: mod.theme()
            }
          end)

        render(conn, :home, domains: domains)

      domain ->
        redirect(conn, to: "#{domain.path_prefix()}/login")
    end
  end
end
