defmodule Ledgr.Domains.AumentaMiPension.CustomerReset do
  @moduledoc """
  Phase 1 reset operations for AMP customers — clears bot conversation state
  while preserving the customer record (and payment history in Ledgr's
  `stripe_payments` table).

  ## Levels

      :conversation
          Deletes the customer's conversations, messages, outbound_messages,
          consultations, consultation_calls, and pension_cases. Customer row
          + onboarding fields preserved. On the next inbound message the bot
          creates a fresh conversation but knows who the customer is.

      :onboarding
          Same as `:conversation`, plus NULLs out the customer's onboarding
          fields (full_name, CURP, NSS, weeks contributed, terms acceptance,
          etc.). The bot will re-ask everything from scratch on next message.

  ## Stripe payments

  Local `stripe_payments` rows have their `consultation_id` pointer NULLed
  (they remain in the Payments report but become unlinked from the
  now-deleted consultations).

  ## Phase 1 caveat

  Ledgr issues these deletes directly against tables owned by the upstream
  Python bot service. There's a brief window where the bot's in-memory state
  may be stale. Acceptable for testing; production-grade reset will move
  behind a bot-service endpoint (Phase 2).
  """

  require Logger
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.AumentaMiPension.StripePayments.StripePayment

  @valid_levels ~w[conversation onboarding]a

  def valid_levels, do: @valid_levels

  @doc """
  Resets the customer at the given level. Runs in a single transaction.
  Returns `{:ok, summary}` with row counts, or `{:error, reason}`.
  """
  def reset(customer_id, level) when is_binary(customer_id) and level in @valid_levels do
    Repo.transaction(fn ->
      conv_ids = lookup_conversation_ids(customer_id)
      cons_ids = lookup_consultation_ids(conv_ids)

      payments_exists? = table_exists?("payments")

      counts = %{
        level: level,
        customer_id: customer_id,
        conversations: length(conv_ids),
        consultations: length(cons_ids),
        consultation_calls: count_in("consultation_calls", "consultation_id", cons_ids),
        messages: count_in("messages", "conversation_id", conv_ids),
        outbound_messages: count_in("outbound_messages", "conversation_id", conv_ids),
        pension_cases: count_in("pension_cases", "conversation_id", conv_ids),
        payments:
          if(payments_exists?, do: count_in("payments", "conversation_id", conv_ids), else: 0),
        stripe_payments_unlinked: count_stripe_payments_for(cons_ids)
      }

      # Order matters: children before parents (no CASCADE on FKs).
      unlink_stripe_payments(cons_ids)
      delete_in("consultation_calls", "consultation_id", cons_ids)
      delete_in("consultations", "conversation_id", conv_ids)
      delete_in("pension_cases", "conversation_id", conv_ids)
      delete_in("messages", "conversation_id", conv_ids)
      delete_in("outbound_messages", "conversation_id", conv_ids)

      # `payments` is upstream-owned and only exists in some environments
      # (prod has it, dev branch doesn't). Skip when absent.
      if payments_exists? do
        delete_in("payments", "conversation_id", conv_ids)
      end

      Repo.active_repo().query!(
        "DELETE FROM conversations WHERE customer_id = $1",
        [customer_id]
      )

      if level == :onboarding do
        nullify_onboarding(customer_id)
      end

      Logger.info(
        "[AumentaMiPension Reset] level=#{level} customer=#{customer_id} #{inspect(counts)}"
      )

      counts
    end)
  end

  def reset(_, level), do: {:error, {:invalid_level, level}}

  # ── helpers ────────────────────────────────────────────────────────────

  defp lookup_conversation_ids(customer_id) do
    {:ok, %{rows: rows}} =
      Repo.active_repo().query(
        "SELECT id FROM conversations WHERE customer_id = $1",
        [customer_id]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  defp lookup_consultation_ids([]), do: []

  defp lookup_consultation_ids(conv_ids) do
    {:ok, %{rows: rows}} =
      Repo.active_repo().query(
        "SELECT id FROM consultations WHERE conversation_id = ANY($1)",
        [conv_ids]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  defp table_exists?(table) do
    {:ok, %{num_rows: n}} =
      Repo.active_repo().query(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1",
        [table]
      )

    n > 0
  end

  defp count_in(_table, _col, []), do: 0

  defp count_in(table, col, ids) do
    {:ok, %{rows: [[c]]}} =
      Repo.active_repo().query(
        "SELECT COUNT(*) FROM #{table} WHERE #{col} = ANY($1)",
        [ids]
      )

    c
  end

  defp delete_in(_table, _col, []), do: :ok

  defp delete_in(table, col, ids) do
    Repo.active_repo().query!(
      "DELETE FROM #{table} WHERE #{col} = ANY($1)",
      [ids]
    )

    :ok
  end

  defp count_stripe_payments_for([]), do: 0

  defp count_stripe_payments_for(ids) do
    StripePayment
    |> where([p], p.consultation_id in ^ids)
    |> Repo.aggregate(:count)
  end

  defp unlink_stripe_payments([]), do: :ok

  defp unlink_stripe_payments(ids) do
    StripePayment
    |> where([p], p.consultation_id in ^ids)
    |> Repo.update_all(set: [consultation_id: nil])

    :ok
  end

  defp nullify_onboarding(customer_id) do
    Repo.active_repo().query!(
      """
      UPDATE customers SET
        display_name = NULL,
        full_name = NULL,
        date_of_birth = NULL,
        gender = NULL,
        curp = NULL,
        nss = NULL,
        weeks_contributed = NULL,
        last_registered_salary = NULL,
        current_employment_status = NULL,
        ley_73 = NULL,
        last_imss_contribution_date = NULL,
        terms_accepted = false,
        terms_accepted_at = NULL,
        updated_at = NOW()
      WHERE id = $1
      """,
      [customer_id]
    )

    :ok
  end
end
