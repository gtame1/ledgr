defmodule LedgrWeb.Domains.MrMunchMe.DiscountCodeHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  import Phoenix.Naming

  embed_templates "discount_code_html/*"
end

defmodule LedgrWeb.Domains.MrMunchMe.DiscountCodeController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.MrMunchMe.Orders
  alias Ledgr.Domains.MrMunchMe.Orders.DiscountCode

  def index(conn, _params) do
    codes = Orders.list_discount_codes()
    render(conn, :index, discount_codes: codes)
  end

  def new(conn, _params) do
    changeset = DiscountCode.changeset(%DiscountCode{}, %{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/discount-codes"))
  end

  def create(conn, %{"discount_code" => attrs}) do
    case Orders.create_discount_code(attrs) do
      {:ok, _code} ->
        conn
        |> put_flash(:info, "Discount code created.")
        |> redirect(to: dp(conn, "/discount-codes"))

      {:error, changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/discount-codes"))
    end
  end

  def edit(conn, %{"id" => id}) do
    code = Orders.get_discount_code!(id)
    changeset = DiscountCode.changeset(code, %{})
    render(conn, :edit, discount_code: code, changeset: changeset, action: dp(conn, "/discount-codes/#{id}"))
  end

  def update(conn, %{"id" => id, "discount_code" => attrs}) do
    code = Orders.get_discount_code!(id)

    case Orders.update_discount_code(code, attrs) do
      {:ok, _code} ->
        conn
        |> put_flash(:info, "Discount code updated.")
        |> redirect(to: dp(conn, "/discount-codes"))

      {:error, changeset} ->
        render(conn, :edit, discount_code: code, changeset: changeset, action: dp(conn, "/discount-codes/#{id}"))
    end
  end

  def delete(conn, %{"id" => id}) do
    code = Orders.get_discount_code!(id)
    {:ok, _} = Orders.delete_discount_code(code)

    conn
    |> put_flash(:info, "Discount code deleted.")
    |> redirect(to: dp(conn, "/discount-codes"))
  end
end
