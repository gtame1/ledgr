defmodule Mix.Tasks.Hd.MedikitBackfillSpecialties do
  @shortdoc "Backfill doctors.medikit_specialty_id from the free-text specialty"

  @moduledoc """
  Populates `doctors.medikit_specialty_id` for active doctors that don't have one
  yet, by name-resolving the doctor's free-text `specialty` against the Medikit
  catalog (`Ledgr.Domains.HelloDoctor.MedikitSpecialties.resolve_id/1`, which is
  accent- and case-insensitive).

  Doctors whose specialty doesn't confidently resolve are left NULL and listed
  so an operator can set the Medikit specialty by hand in the doctor form — the
  provisioning backfill then picks them up. Never guesses.

  ## Usage

      mix hd.medikit_backfill_specialties          # dry run — shows what would change
      mix hd.medikit_backfill_specialties --fix    # apply the updates

  Requires the HD DB (HELLO_DOCTOR_DATABASE_URL) to be reachable.
  """

  use Mix.Task
  import Ecto.Query

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.MedikitSpecialties

  @requirements ["app.start"]

  def run(args) do
    apply? = "--fix" in args
    Repo.put_active_repo(Ledgr.Repos.HelloDoctor)

    doctors =
      from(d in Doctor,
        where:
          is_nil(d.deactivated_at) and
            is_nil(d.medikit_specialty_id) and
            not is_nil(d.specialty) and d.specialty != ""
      )
      |> Repo.all()

    {resolved, unresolved} =
      doctors
      |> Enum.map(fn d -> {d, MedikitSpecialties.resolve_id(d.specialty)} end)
      |> Enum.split_with(fn {_d, id} -> not is_nil(id) end)

    Mix.shell().info(
      "\n#{length(doctors)} active doctor(s) without a Medikit specialty; " <>
        "#{length(resolved)} resolvable, #{length(unresolved)} need manual selection.\n"
    )

    Enum.each(resolved, fn {d, id} ->
      Mix.shell().info("  [resolve] #{d.id}  #{d.specialty} -> #{id}")
    end)

    if unresolved != [] do
      Mix.shell().info("\nUnresolved (set the Medikit specialty in the doctor form):")
      Enum.each(unresolved, fn {d, _} -> Mix.shell().info("  #{d.id}  #{d.specialty}") end)
    end

    cond do
      resolved == [] ->
        Mix.shell().info("\nNothing to update.")

      apply? ->
        {count, _} =
          Enum.reduce(resolved, {0, nil}, fn {d, id}, {n, _} ->
            {:ok, _} = Repo.update(Ecto.Changeset.change(d, medikit_specialty_id: id))
            {n + 1, nil}
          end)

        Mix.shell().info("\nUpdated #{count} doctor(s).")

      true ->
        Mix.shell().info(
          "\nDry run — re-run with --fix to apply the #{length(resolved)} update(s)."
        )
    end
  end
end
