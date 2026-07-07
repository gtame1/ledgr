defmodule Ledgr.Domains.HelloDoctor.MarketingCostAccounting do
  @moduledoc """
  Posts marketing / ad spend to the HelloDoctor GL.

  Each marketing_cost row becomes a balanced journal entry:

      DEBIT  6050  Marketing & Advertising          $X.XX MXN
      CREDIT 2310  Accounts Payable - Marketing      $X.XX MXN

  Amounts uploaded in USD are converted to MXN using the shared USD/MXN rate
  (`Ledgr.Core.Settings.get_usd_mxn_rate/0`); MXN uploads post 1:1.

  Idempotent — `post_to_gl/1` skips a row that already has `posted_at`. Deleting
  a posted row posts a reversing entry first so the ledger stays balanced.
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Settings
  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost

  import Ecto.Query, warn: false

  @marketing_expense_code "6050"
  @marketing_payable_code "2310"

  @doc """
  Posts a single marketing_cost row to the GL. Returns `{:ok, updated}`,
  `{:ok, :already_posted, cost}`, or `{:error, reason}`.
  """
  def post_to_gl(%MarketingCost{posted_at: posted} = cost) when not is_nil(posted),
    do: {:ok, :already_posted, cost}

  def post_to_gl(%MarketingCost{} = cost) do
    fx_rate = fx_rate_for(cost.currency)
    amount_mxn_cents = round(cost.amount * fx_rate * 100)

    if amount_mxn_cents <= 0 do
      {:error, :zero_amount}
    else
      expense = Accounting.get_account_by_code!(@marketing_expense_code)
      payable = Accounting.get_account_by_code!(@marketing_payable_code)
      label = platform_label(cost.platform)
      fx_note = if cost.currency == "MXN", do: "", else: " @ #{fx_rate} MXN/#{cost.currency}"

      entry_attrs = %{
        date: cost.date,
        entry_type: "marketing_cost",
        reference: "MktCost #{cost.id}",
        description: "#{label} ad spend — #{cost.date}#{fx_note}",
        payee: label
      }

      lines = [
        %{
          account_id: expense.id,
          debit_cents: amount_mxn_cents,
          credit_cents: 0,
          description: "#{label} ad spend — #{cost.date}"
        },
        %{
          account_id: payable.id,
          debit_cents: 0,
          credit_cents: amount_mxn_cents,
          description: "Payable to #{label} — #{cost.date}"
        }
      ]

      case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
        {:ok, entry} ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          updated =
            cost
            |> MarketingCost.changeset(%{
              posted_at: now,
              journal_entry_id: entry.id,
              fx_rate: fx_rate,
              spend_mxn_cents: amount_mxn_cents
            })
            |> Repo.update!()

          Logger.info(
            "[MarketingCostAccounting] Posted cost #{cost.id} (#{label}) → JE ##{entry.id}: #{amount_mxn_cents} centavos MXN"
          )

          {:ok, updated}

        {:error, changeset} ->
          Logger.error(
            "[MarketingCostAccounting] Failed to post cost #{cost.id}: #{inspect(changeset)}"
          )

          {:error, changeset}
      end
    end
  end

  @doc "Posts every unposted marketing_cost. Returns %{posted, skipped, errors}."
  def post_all_unposted do
    MarketingCost
    |> where([c], is_nil(c.posted_at))
    |> order_by([c], asc: :date, asc: :platform)
    |> Repo.all()
    |> Enum.reduce(%{posted: 0, skipped: 0, errors: 0}, fn cost, acc ->
      case post_to_gl(cost) do
        {:ok, :already_posted, _} -> %{acc | skipped: acc.skipped + 1}
        {:ok, _} -> %{acc | posted: acc.posted + 1}
        {:error, :zero_amount} -> %{acc | skipped: acc.skipped + 1}
        {:error, _} -> %{acc | errors: acc.errors + 1}
      end
    end)
  end

  @doc """
  Deletes a marketing_cost row. If it was posted, posts a reversing entry
  (DEBIT 2310 / CREDIT 6050) first so the GL stays balanced, then deletes the
  row (the original + reversal JEs remain as the audit trail).
  """
  def delete_cost(%MarketingCost{} = cost) do
    Repo.transaction(fn ->
      if cost.posted_at && cost.spend_mxn_cents && cost.spend_mxn_cents > 0 do
        expense = Accounting.get_account_by_code!(@marketing_expense_code)
        payable = Accounting.get_account_by_code!(@marketing_payable_code)
        label = platform_label(cost.platform)

        entry_attrs = %{
          date: cost.date,
          entry_type: "marketing_cost_reversal",
          reference: "MktCost #{cost.id} reversal",
          description: "Reverse #{label} ad spend — #{cost.date} (row deleted)",
          payee: label
        }

        lines = [
          %{
            account_id: payable.id,
            debit_cents: cost.spend_mxn_cents,
            credit_cents: 0,
            description: "Reverse marketing payable"
          },
          %{
            account_id: expense.id,
            debit_cents: 0,
            credit_cents: cost.spend_mxn_cents,
            description: "Reverse marketing expense"
          }
        ]

        case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end

      Repo.delete!(cost)
    end)
  end

  @doc "All marketing_costs, newest-first."
  def list_all do
    MarketingCost
    |> order_by([c], desc: :date, asc: :platform)
    |> Repo.all()
  end

  # 1:1 for MXN; shared USD/MXN rate otherwise.
  defp fx_rate_for("MXN"), do: 1.0
  defp fx_rate_for(_), do: Settings.get_usd_mxn_rate()

  defp platform_label("meta"), do: "Meta"
  defp platform_label("google"), do: "Google Ads"
  defp platform_label("google_ads"), do: "Google Ads"
  defp platform_label("tiktok"), do: "TikTok"
  defp platform_label(other) when is_binary(other), do: String.capitalize(other)
  defp platform_label(_), do: "Marketing"
end
