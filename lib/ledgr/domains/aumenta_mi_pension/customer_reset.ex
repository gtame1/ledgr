defmodule Ledgr.Domains.AumentaMiPension.CustomerReset do
  @moduledoc """
  Customer reset for AMP — delegates to the bot service's
  `/admin/customers/:phone/reset` endpoint.

  The bot service owns the conversation/message/customer state, so reset is
  its operation. Ledgr just calls it (with dry-run preview, then confirm) and
  surfaces the result to the admin. After a real reset, Ledgr does light
  housekeeping on its own `stripe_payments` table to NULL `consultation_id`
  pointers that no longer reference an existing consultation.

  See `Ledgr.Domains.AumentaMiPension.BotApi` for the HTTP wrapper.
  """

  require Logger
  alias Ledgr.Domains.AumentaMiPension.BotApi
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment
  alias Ledgr.Repo
  import Ecto.Query, warn: false

  @doc """
  Previews a reset (calls the bot endpoint with `dry_run: true`).
  """
  def preview(phone, opts \\ []) do
    BotApi.reset_customer(phone, Keyword.put(opts, :dry_run, true))
  end

  @doc """
  Executes a reset (calls the bot endpoint with `dry_run: false`).
  After the bot succeeds, NULLs `stripe_payments.consultation_id` for any
  Ledgr-side payment rows that point at a consultation the bot just deleted.
  """
  def execute(phone, opts \\ []) do
    case BotApi.reset_customer(phone, Keyword.put(opts, :dry_run, false)) do
      {:ok, response} ->
        unlinked = housekeep_stripe_payments()
        {:ok, Map.put(response, "stripe_payments_unlinked", unlinked)}

      other ->
        other
    end
  end

  # NULLs consultation_id on stripe_payments rows whose target consultation
  # no longer exists. Idempotent — safe to run any time. Returns count of
  # rows updated.
  defp housekeep_stripe_payments do
    {n, _} =
      from(p in StripePayment,
        where: not is_nil(p.consultation_id),
        where:
          fragment(
            "NOT EXISTS (SELECT 1 FROM consultations c WHERE c.id = ?)",
            p.consultation_id
          )
      )
      |> Repo.update_all(set: [consultation_id: nil])

    n
  end
end
