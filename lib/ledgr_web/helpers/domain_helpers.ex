defmodule LedgrWeb.Helpers.DomainHelpers do
  @moduledoc """
  Helpers for building domain-scoped URL paths.

  Provides `dp/2` (domain path) which prepends the current domain's path
  prefix to a relative path. Works in both controllers and templates.

  ## Usage in controllers

      redirect(to: dp(conn, "/expenses/\#{expense.id}"))

  ## Usage in templates

      <.link navigate={dp(@domain_path_prefix, "/reports/pnl")}>P&L</.link>
  """

  @doc """
  Builds a domain-scoped path by prepending the domain prefix.

  Accepts either a `Plug.Conn` (for controllers) or a path prefix string
  (for templates where `@domain_path_prefix` is available).

  ## Examples

      dp(conn, "/expenses")
      #=> "/app/mr-munch-me/expenses"

      dp(@domain_path_prefix, "/reports/pnl")
      #=> "/app/mr-munch-me/reports/pnl"

      dp(conn, "/")
      #=> "/app/mr-munch-me"
  """
  def dp(%Plug.Conn{} = conn, path) do
    prefix = conn.assigns[:domain_path_prefix] || ""
    join_path(prefix, path)
  end

  def dp(prefix, path) when is_binary(prefix) do
    join_path(prefix, path)
  end

  defp join_path("", path), do: path
  defp join_path(prefix, "/"), do: prefix
  defp join_path(prefix, path), do: prefix <> path

  @doc "Returns today's date in Mexico City timezone."
  def today_mx do
    DateTime.now!("America/Mexico_City") |> DateTime.to_date()
  end
end
