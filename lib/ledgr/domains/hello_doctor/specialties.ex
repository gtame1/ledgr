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

  def update_specialty(%Specialty{} = specialty, attrs) do
    specialty
    |> Specialty.changeset(attrs)
    |> Repo.update()
  end

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

  @doc """
  Replaces the entire specialties table with the Prescrypto catalog.
  Preserves each specialty's is_active flag if it was previously set.
  Returns the number of rows inserted.
  """
  def replace_from_prescrypto(prescrypto_specialties) when is_list(prescrypto_specialties) do
    # Snapshot existing is_active state keyed by prescrypto_specialty_id
    active_states =
      Specialty
      |> select([s], {s.prescrypto_specialty_id, s.is_active})
      |> Repo.all()
      |> Map.new()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(prescrypto_specialties, fn %{id: id, name: name} ->
        %{
          name: name,
          prescrypto_specialty_id: id,
          is_active: Map.get(active_states, id, true),
          created_at: now
        }
      end)

    Repo.delete_all(Specialty)
    {count, _} = Repo.insert_all(Specialty, rows)
    count
  end

  @doc """
  Returns the Prescrypto specialty ID for the given specialty name, or nil if
  the specialty doesn't exist or has no Prescrypto ID mapped yet.
  """
  def prescrypto_specialty_id_for(name) when is_binary(name) do
    Specialty
    |> where([s], s.name == ^name)
    |> select([s], s.prescrypto_specialty_id)
    |> Repo.one()
  end

  def prescrypto_specialty_id_for(_), do: nil
end
