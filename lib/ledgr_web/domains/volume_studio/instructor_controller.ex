defmodule LedgrWeb.Domains.VolumeStudio.InstructorController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.Instructors
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor

  def index(conn, _params) do
    instructors = Instructors.list_instructors()
    render(conn, :index, instructors: instructors)
  end

  def new(conn, _params) do
    changeset = Instructors.change_instructor(%Instructor{})
    render(conn, :new, changeset: changeset, action: dp(conn, "/instructors"))
  end

  def create(conn, %{"instructor" => params}) do
    case Instructors.create_instructor(params) do
      {:ok, _instructor} ->
        conn
        |> put_flash(:info, "Instructor created successfully.")
        |> redirect(to: dp(conn, "/instructors"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset, action: dp(conn, "/instructors"))
    end
  end

  def edit(conn, %{"id" => id}) do
    instructor = Instructors.get_instructor!(id)
    changeset = Instructors.change_instructor(instructor)
    render(conn, :edit,
      instructor: instructor,
      changeset: changeset,
      action: dp(conn, "/instructors/#{id}")
    )
  end

  def update(conn, %{"id" => id, "instructor" => params}) do
    instructor = Instructors.get_instructor!(id)

    case Instructors.update_instructor(instructor, params) do
      {:ok, _instructor} ->
        conn
        |> put_flash(:info, "Instructor updated successfully.")
        |> redirect(to: dp(conn, "/instructors"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          instructor: instructor,
          changeset: changeset,
          action: dp(conn, "/instructors/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    instructor = Instructors.get_instructor!(id)

    case Instructors.delete_instructor(instructor) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Instructor deleted.")
        |> redirect(to: dp(conn, "/instructors"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Cannot delete this instructor — they have class sessions or consultations.")
        |> redirect(to: dp(conn, "/instructors"))
    end
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.InstructorHTML do
  use LedgrWeb, :html

  embed_templates "instructor_html/*"
end
