defmodule Ledgr.Domains.HelloDoctor.Specialties do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Specialties.Specialty

  def list_specialties do
    Specialty
    |> order_by(:name)
    |> Repo.all()
  end

  def list_active_specialties do
    Specialty
    |> where([s], s.is_active == true)
    |> order_by(:name)
    |> Repo.all()
  end

  def get_specialty!(id), do: Repo.get!(Specialty, id)

  def create_specialty(attrs) do
    %Specialty{}
    |> Specialty.changeset(attrs)
    |> Repo.insert()
  end

  def delete_specialty(%Specialty{} = specialty), do: Repo.delete(specialty)

  def toggle_specialty(%Specialty{} = specialty) do
    specialty
    |> Specialty.changeset(%{is_active: !specialty.is_active})
    |> Repo.update()
  end

  def change_specialty(%Specialty{} = specialty, attrs \\ %{}) do
    Specialty.changeset(specialty, attrs)
  end

  @doc "Returns [{name, name}] tuples for use in select inputs."
  def specialty_options do
    list_active_specialties()
    |> Enum.map(&{&1.name, &1.name})
  end
end
