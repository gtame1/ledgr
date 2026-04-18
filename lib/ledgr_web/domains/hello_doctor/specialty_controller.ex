defmodule LedgrWeb.Domains.HelloDoctor.SpecialtyController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Specialties
  alias Ledgr.Domains.HelloDoctor.Specialties.Specialty

  def index(conn, _params) do
    specialties = Specialties.list_specialties()
    changeset = Specialties.change_specialty(%Specialty{})
    render(conn, :index, specialties: specialties, changeset: changeset)
  end

  def create(conn, %{"specialty" => params}) do
    case Specialties.create_specialty(params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Specialty added.")
        |> redirect(to: dp(conn, "/specialties"))

      {:error, changeset} ->
        specialties = Specialties.list_specialties()
        render(conn, :index, specialties: specialties, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    specialty = Specialties.get_specialty!(id)

    case Specialties.delete_specialty(specialty) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Specialty removed.")
        |> redirect(to: dp(conn, "/specialties"))

      {:error, _} ->
        conn
        |> put_flash(:error, "Cannot delete — specialty is in use by one or more doctors.")
        |> redirect(to: dp(conn, "/specialties"))
    end
  end

  def toggle(conn, %{"id" => id}) do
    specialty = Specialties.get_specialty!(id)

    case Specialties.toggle_specialty(specialty) do
      {:ok, _} -> redirect(conn, to: dp(conn, "/specialties"))
      {:error, _} -> redirect(conn, to: dp(conn, "/specialties"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.SpecialtyHTML do
  use LedgrWeb, :html
  embed_templates "specialty_html/*"
end
