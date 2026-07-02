defmodule Mix.Tasks.Hd.MedikitProvision do
  @shortdoc "Provision Hello Doctor doctors as Medikit HealthcareProviders"

  @moduledoc """
  Runs the idempotent, fail-closed Medikit provisioning backfill over every
  active Hello Doctor doctor that isn't provisioned yet
  (`Ledgr.Domains.HelloDoctor.MedikitProvisioning.run/0`).

  For each candidate it validates the cédula, registers the doctor with Medikit,
  and writes `medikit_healthcare_provider_id` + `medikit_license_validated_at`.
  Any failure leaves the column NULL so the next run retries — never a
  placeholder.

  ## Usage

      # Requires the Medikit env (MEDIKIT_API_KEY, MEDIKIT_DOCTORS_HOST,
      # MEDIKIT_PAYER_ID, MEDIKIT_PURCHASER_PLAN_ID, ...) and the HD DB
      # (HELLO_DOCTOR_DATABASE_URL) to be set.
      mix hd.medikit_provision

  Prints the summary map (provisioned / invalid_license / incomplete / failed /
  total) and, when any doctor was skipped or failed, the per-doctor outcomes so
  the operator knows what to fix.
  """

  use Mix.Task

  alias Ledgr.Domains.HelloDoctor.Medikit
  alias Ledgr.Domains.HelloDoctor.MedikitProvisioning

  @requirements ["app.start"]

  def run(_args) do
    unless Medikit.enabled?() do
      Mix.raise(
        "Medikit is not configured — set MEDIKIT_API_KEY + MEDIKIT_DOCTORS_HOST " <>
          "(and the account ids) before running this task."
      )
    end

    summary = MedikitProvisioning.run()

    Mix.shell().info("""

    Medikit provisioning summary
    ============================
      total:           #{summary.total}
      provisioned:     #{summary.provisioned}
      invalid_license: #{summary.invalid_license}
      incomplete:      #{summary.incomplete}
      failed:          #{summary.failed}
    """)

    non_provisioned =
      Enum.reject(summary.results, fn {_id, outcome} -> match?({:provisioned, _}, outcome) end)

    if non_provisioned != [] do
      Mix.shell().info("Doctors not provisioned this run (id — outcome):")

      Enum.each(non_provisioned, fn {id, outcome} ->
        Mix.shell().info("  #{id} — #{inspect(outcome)}")
      end)
    end
  end
end
