defmodule LedgrWeb.Domains.VolumeStudio.SpaceController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Spaces
  alias Ledgr.Domains.VolumeStudio.Spaces.Space
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    spaces = Spaces.list_spaces()
    render(conn, :index, spaces: spaces)
  end

  def new(conn, _params) do
    changeset = Spaces.change_space(%Space{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/spaces"))
  end

  def create(conn, %{"space" => params}) do
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:hourly_rate_cents])

    case Spaces.create_space(params) do
      {:ok, _space} ->
        conn
        |> put_flash(:info, "Space created successfully.")
        |> redirect(to: dp(conn, "/spaces"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/spaces"))
    end
  end

  def edit(conn, %{"id" => id}) do
    space = Spaces.get_space!(id)
    attrs = %{"hourly_rate_cents" => MoneyHelper.cents_to_pesos(space.hourly_rate_cents || 0)}
    changeset = Spaces.change_space(space, attrs)
    render(conn, :edit,
      space: space,
      changeset: changeset,
      action: dp(conn, "/spaces/#{id}")
    )
  end

  def update(conn, %{"id" => id, "space" => params}) do
    space = Spaces.get_space!(id)
    params = MoneyHelper.convert_params_pesos_to_cents(params, [:hourly_rate_cents])

    case Spaces.update_space(space, params) do
      {:ok, _space} ->
        conn
        |> put_flash(:info, "Space updated successfully.")
        |> redirect(to: dp(conn, "/spaces"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          space: space,
          changeset: changeset,
          action: dp(conn, "/spaces/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    space = Spaces.get_space!(id)

    case Spaces.delete_space(space) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Space deleted.")
        |> redirect(to: dp(conn, "/spaces"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete this space — it has rental records.")
        |> redirect(to: dp(conn, "/spaces"))
    end
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.SpaceHTML do
  use LedgrWeb, :html

  embed_templates "space_html/*"
end
