defmodule Ledgr.Domains.VolumeStudio.Instructors do
  @moduledoc """
  Context module for managing Volume Studio instructors.
  """

  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.VolumeStudio.Instructors.Instructor

  @doc "Returns all instructors, ordered by name."
  def list_instructors do
    Instructor
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Returns only active instructors, ordered by name. Useful for select dropdowns."
  def list_active_instructors do
    Instructor
    |> where(active: true)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc "Gets a single instructor. Raises if not found."
  def get_instructor!(id), do: Repo.get!(Instructor, id)

  @doc "Returns a changeset for the given instructor and attrs."
  def change_instructor(%Instructor{} = instructor, attrs \\ %{}) do
    Instructor.changeset(instructor, attrs)
  end

  @doc "Creates an instructor."
  def create_instructor(attrs \\ %{}) do
    %Instructor{}
    |> Instructor.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an instructor."
  def update_instructor(%Instructor{} = instructor, attrs) do
    instructor
    |> Instructor.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes an instructor. FK constraints will surface errors if referenced by sessions/consultations."
  def delete_instructor(%Instructor{} = instructor) do
    Repo.delete(instructor)
  end
end
