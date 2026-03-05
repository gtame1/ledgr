defmodule LedgrWeb.PageController do
  use LedgrWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: "/mr-munch-me/menu")
  end
end
