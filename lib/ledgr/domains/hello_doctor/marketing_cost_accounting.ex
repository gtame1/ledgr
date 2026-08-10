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
