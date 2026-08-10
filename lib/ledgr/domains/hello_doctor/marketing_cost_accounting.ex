defmodule Ledgr.Domains.HelloDoctor.MarketingCostAccounting do
  @moduledoc """
  Posts marketing / ad spend to the HelloDoctor GL.

  Each marketing_cost row becomes a balanced journal entry:

      DEBIT  6050  Marketing & Advertising          $X.XX MXN
      CREDIT 2310  Accounts Payable - Marketing      $X.XX MXN

  A row with a **negative** amount is a credit (promo credit, refund or billing
  adjustment on the platform's invoice) and posts the same entry with the two
  sides swapped, so it reduces marketing expense:

      DEBIT  2310  Accounts Payable - Marketing     $X.XX MXN
      CREDIT 6050  Marketing & Advertising           $X.XX MXN

  The magnitude is always positive — `JournalLine` rejects negative debit or
  credit cents — so the sign is carried by which side each account lands on.
  `spend_mxn_cents` on the row itself stays signed, which is what lets the
  analytics SUMs net credits against spend.

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
  def post_to_gl(%MarketingCost{} = cost), do: post_to_gl(cost, gl_accounts())

  @doc """
  The two GL accounts a marketing cost posts to. Fetch once and pass to
  `post_to_gl/2` when posting many rows so a bulk import doesn't re-query the
  same two accounts hundreds of times inside a single transaction (that
  starved the small prod pool and blew the 15s connection-checkout timeout).
  """
  def gl_accounts do
    %{
      expense: Accounting.get_account_by_code!(@marketing_expense_code),
      payable: Accounting.get_account_by_code!(@marketing_payable_code)
    }
  end

  def post_to_gl(%MarketingCost{posted_at: posted} = cost, _accts) when not is_nil(posted),
    do: {:ok, :already_posted, cost}

  def post_to_gl(%MarketingCost{} = cost, %{expense: expense, payable: payable}) do
    fx_rate = fx_rate_for(cost.currency)
    amount_mxn_cents = round(cost.amount * fx_rate * 100)

    if amount_mxn_cents == 0 do
      {:error, :zero_amount}
    else
      label = platform_label(cost.platform)
      fx_note = if cost.currency == "MXN", do: "", else: " @ #{fx_rate} MXN/#{cost.currency}"
      credit? = amount_mxn_cents < 0
      noun = if credit?, do: "credit", else: "spend"

      entry_attrs = %{
        date: cost.date,
        entry_type: "marketing_cost",
        reference: "MktCost #{cost.id}",
        description: "#{label} ad #{noun} — #{cost.date}#{fx_note}",
        payee: label
      }

      lines = gl_lines(credit?, expense, payable, abs(amount_mxn_cents), label, cost.date)

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

  # Spend debits the expense and credits the payable. A credit (negative
  # amount — promo credit, refund, billing adjustment) flips both sides, so the
  # magnitudes stay positive: `JournalLine` rejects negative debit/credit cents,
  # which is why the sign lives in the choice of side rather than in the number.
  defp gl_lines(false = _credit?, expense, payable, cents, label, date) do
    [
      %{
        account_id: expense.id,
        debit_cents: cents,
        credit_cents: 0,
        description: "#{label} ad spend — #{date}"
      },
      %{
        account_id: payable.id,
        debit_cents: 0,
        credit_cents: cents,
        description: "Payable to #{label} — #{date}"
      }
    ]
  end

  defp gl_lines(true = _credit?, expense, payable, cents, label, date) do
    [
      %{
        account_id: payable.id,
        debit_cents: cents,
        credit_cents: 0,
        description: "Credit from #{label} — #{date}"
      },
      %{
        account_id: expense.id,
        debit_cents: 0,
        credit_cents: cents,
        description: "#{label} ad credit — #{date}"
      }
    ]
  end

  @doc """
  Revises a charge's amount after the platform restated it, and posts a GL
  adjustment for the difference.

  The original entry is left alone and a separate `marketing_cost_adjustment`
  entry carries the delta, so the ledger shows what was booked and when it was
  corrected rather than quietly rewriting history. A delta that increases spend
  posts like spend (DEBIT 6050); one that decreases it posts like a credit.

  The UPDATE is guarded on the amount we read, so two concurrent imports of the
  same restatement can't both apply the delta — the loser matches zero rows and
  gets `{:ok, :already_applied}`. Returns `{:ok, cost}`, `{:ok, :no_change}`,
  `{:ok, :already_applied}`, or `{:error, reason}`.
  """
  def restate(%MarketingCost{} = cost, new_amount) when is_number(new_amount) do
    cond do
      new_amount == cost.amount ->
        {:ok, :no_change}

      # Never posted, so nothing to adjust — just correct the figure.
      is_nil(cost.posted_at) ->
        guarded_update(cost, new_amount, %{})

      true ->
        fx_rate = cost.fx_rate || fx_rate_for(cost.currency)
        new_cents = round(new_amount * fx_rate * 100)
        delta_cents = new_cents - (cost.spend_mxn_cents || 0)

        # Claim the row FIRST. The guarded UPDATE is what makes this safe under
        # concurrency, so it has to win or lose before anything reaches the GL —
        # posting the adjustment first would double-book the delta for a racing
        # caller holding the same stale struct.
        Repo.transaction(fn ->
          case guarded_update(cost, new_amount, %{
                 spend_mxn_cents: new_cents,
                 fx_rate: fx_rate
               }) do
            {:ok, :already_applied} ->
              :already_applied

            {:ok, updated} ->
              case post_adjustment(cost, delta_cents) do
                :ok -> updated
                {:error, reason} -> Repo.rollback(reason)
              end
          end
        end)
    end
  end

  # A zero delta can happen when two different uploaded amounts round to the
  # same centavo (USD at a coarse rate); correct the row, post nothing.
  defp post_adjustment(_cost, 0), do: :ok

  defp post_adjustment(%MarketingCost{} = cost, delta_cents) do
    accts = gl_accounts()
    label = platform_label(cost.platform)
    credit? = delta_cents < 0

    entry_attrs = %{
      date: cost.date,
      entry_type: "marketing_cost_adjustment",
      reference: "MktCost #{cost.id} adjustment",
      description:
        "#{label} ad spend restated — #{cost.date} " <>
          "(#{format_signed(delta_cents)} MXN)",
      payee: label
    }

    lines =
      gl_lines(credit?, accts.expense, accts.payable, abs(delta_cents), label, cost.date)

    case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
      {:ok, _entry} ->
        Logger.info(
          "[MarketingCostAccounting] Restated cost #{cost.id} (#{label}): #{format_signed(delta_cents)} centavos MXN"
        )

        :ok

      {:error, changeset} ->
        Logger.error(
          "[MarketingCostAccounting] Failed to adjust cost #{cost.id}: #{inspect(changeset)}"
        )

        {:error, changeset}
    end
  end

  # Optimistic: only revise the row if `amount` still holds the value the delta
  # was computed from.
  defp guarded_update(%MarketingCost{} = cost, new_amount, extra) do
    fields = Map.merge(extra, %{amount: new_amount})

    query =
      from(c in MarketingCost, where: c.id == ^cost.id and c.amount == ^cost.amount)

    case Repo.update_all(query, set: Map.to_list(fields)) do
      {1, _} -> {:ok, Repo.get(MarketingCost, cost.id)}
      {0, _} -> {:ok, :already_applied}
    end
  end

  defp format_signed(cents) when cents >= 0, do: "+#{cents}"
  defp format_signed(cents), do: to_string(cents)

  @doc "Posts every unposted marketing_cost. Returns %{posted, skipped, errors}."
  def post_all_unposted do
    accts = gl_accounts()

    MarketingCost
    |> where([c], is_nil(c.posted_at))
    |> order_by([c], asc: :date, asc: :platform)
    |> Repo.all()
    |> Enum.reduce(%{posted: 0, skipped: 0, errors: 0}, fn cost, acc ->
      case post_to_gl(cost, accts) do
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
      cents = cost.spend_mxn_cents || 0

      if cost.posted_at && cents != 0 do
        expense = Accounting.get_account_by_code!(@marketing_expense_code)
        payable = Accounting.get_account_by_code!(@marketing_payable_code)
        label = platform_label(cost.platform)
        noun = if cents < 0, do: "credit", else: "spend"

        entry_attrs = %{
          date: cost.date,
          entry_type: "marketing_cost_reversal",
          reference: "MktCost #{cost.id} reversal",
          description: "Reverse #{label} ad #{noun} — #{cost.date} (row deleted)",
          payee: label
        }

        # Undo whichever way the original posted: spend (cents > 0) is unwound
        # by the credit-shaped lines, and a credit by the spend-shaped ones.
        lines =
          gl_lines(cents > 0, expense, payable, abs(cents), label, cost.date)
          |> Enum.map(&%{&1 | description: "Reverse: #{&1.description}"})

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
