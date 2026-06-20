defmodule Ledgr.Domains.HelloDoctor.MedikitSpecialties do
  @moduledoc """
  Medikit specialty catalog — the `SpecialtyId` values Medikit's /doctors
  endpoint requires, provided by the Medikit Account Manager.

  Stored as config so it can be filled/updated without a code change:

      config :ledgr, :medikit,
        specialty_catalog: [
          %{id: "0bc8c000000XcmfAAC", name: "Medicina General"},
          %{id: "0bc8c000000XcmgAAC", name: "Cardiología"},
          ...
        ]

  Until the catalog is supplied this returns an empty list, so the doctor-form
  dropdown renders empty and no doctor can be assigned a `medikit_specialty_id`
  (provisioning then skips them — fail-closed).
  """

  @doc "Raw catalog entries: [%{id: String.t(), name: String.t()}]."
  def catalog do
    Application.get_env(:ledgr, :medikit, [])
    |> Keyword.get(:specialty_catalog, [])
  end

  @doc "`[{name, id}]` tuples for a <select> dropdown, sorted by name."
  def options do
    catalog()
    |> Enum.map(&{&1.name, &1.id})
    |> Enum.sort_by(fn {name, _id} -> name end)
  end

  @doc "True if `id` is a known catalog SpecialtyId."
  def valid_id?(id) when is_binary(id) and id != "" do
    Enum.any?(catalog(), &(&1.id == id))
  end

  def valid_id?(_), do: false
end
