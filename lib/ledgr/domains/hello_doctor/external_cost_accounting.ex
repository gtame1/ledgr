defmodule Ledgr.Domains.HelloDoctor.ExternalCostAccounting do
  @moduledoc """
  Posts synced external service costs to the HelloDoctor GL.

  Each external_cost row becomes a balanced journal entry:

      DEBIT  604x  [Service-specific expense account]   $X.XX MXN
      CREDIT 2300  Accounts Payable - Technology        $X.XX MXN

  USD amounts are converted to MXN using a configurable FX rate
  (Application.get_env(:ledgr, :usd_mxn_rate) || 17.5 as default).

  The external_cost row is stamped with posted_at, journal_entry_id,
  fx_rate, and amount_mxn_cents after a successful post.
  """

  require Logger

  alias Ledgr.Repo
  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Settings
  alias Ledgr.Domains.HelloDoctor.ExternalCosts.ExternalCost

  import Ecto.Query, warn: false

  # Account codes
  @ap_technology_code "2300"

  @service_account_codes %{
    "openai"         => "6041",
    "whereby"        => "6042",
    "aws_app_runner" => "6043"
  }

  @service_labels %{
    "openai"         => "OpenAI",
    "whereby"        => "Whereby",
    "aws_app_runner" => "AWS App Runner",
    "evolution_api"  => "Evolution API"
  }

  @doc """
  Posts a single external_cost row to the GL.
  Returns {:ok, updated_cost} or {:error, reason}.
  Idempotent — returns {:ok, :already_posted} if already posted.
  """
  def post_to_gl(%ExternalCost{posted_at: posted} = cost) when not is_nil(posted) do
    {:ok, :already_posted, cost}
  end

  def post_to_gl(%ExternalCost{} = cost) do
    fx_rate = Settings.get_usd_mxn_rate()
    amount_mxn = cost.amount_usd * fx_rate
    amount_mxn_cents = round(amount_mxn * 100)

    if amount_mxn_cents <= 0 do
      {:error, :zero_amount}
    else
      expense_code = Map.get(@service_account_codes, cost.service, "6040")
      service_label = Map.get(@service_labels, cost.service, cost.service)
      model_suffix = if cost.model, do: " (#{cost.model})", else: ""

      expense_account = Accounting.get_account_by_code!(expense_code)
      ap_account      = Accounting.get_account_by_code!(@ap_technology_code)

      entry_attrs = %{
        date:        cost.date,
        entry_type:  "external_cost",
        reference:   "ExtCost #{cost.id}",
        description: "#{service_label}#{model_suffix} — #{cost.date} @ #{fx_rate} MXN/USD",
        payee:       service_label
      }

      lines = [
        %{
          account_id:   expense_account.id,
          debit_cents:  amount_mxn_cents,
          credit_cents: 0,
          description:  "#{service_label}#{model_suffix}: #{Float.round(cost.amount_usd, 4)} USD × #{fx_rate}"
        },
        %{
          account_id:   ap_account.id,
          debit_cents:  0,
          credit_cents: amount_mxn_cents,
          description:  "Payable to #{service_label} — #{cost.date}"
        }
      ]

      case Accounting.create_journal_entry_with_lines(entry_attrs, lines) do
        {:ok, entry} ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          updated =
            cost
            |> ExternalCost.changeset(%{
              posted_at:        now,
              journal_entry_id: entry.id,
              fx_rate:          fx_rate,
              amount_mxn_cents: amount_mxn_cents
            })
            |> Repo.update!()

          Logger.info("[ExternalCostAccounting] Posted cost #{cost.id} (#{service_label}) → JE ##{entry.id}: #{amount_mxn_cents} centavos MXN")
          {:ok, updated}

        {:error, changeset} ->
          Logger.error("[ExternalCostAccounting] Failed to post cost #{cost.id}: #{inspect(changeset)}")
          {:error, changeset}
      end
    end
  end

  @doc """
  Posts all unposted external_costs in a given date range to the GL.
  Returns %{posted: N, skipped: N, errors: N}.
  """
  def post_all_unposted(start_date \\ nil, end_date \\ nil) do
    query =
      ExternalCost
      |> where([c], is_nil(c.posted_at))
      |> then(fn q ->
        if start_date, do: where(q, [c], c.date >= ^start_date), else: q
      end)
      |> then(fn q ->
        if end_date, do: where(q, [c], c.date <= ^end_date), else: q
      end)
      |> order_by([c], [asc: :date, asc: :service])

    costs = Repo.all(query)

    Enum.reduce(costs, %{posted: 0, skipped: 0, errors: 0}, fn cost, acc ->
      case post_to_gl(cost) do
        {:ok, :already_posted, _} -> %{acc | skipped: acc.skipped + 1}
        {:ok, _}                  -> %{acc | posted: acc.posted + 1}
        {:error, :zero_amount}    -> %{acc | skipped: acc.skipped + 1}
        {:error, _}               -> %{acc | errors: acc.errors + 1}
      end
    end)
  end

  @doc "Returns all unposted external_costs, newest-first."
  def unposted_costs do
    ExternalCost
    |> where([c], is_nil(c.posted_at))
    |> order_by([c], [desc: :date, asc: :service])
    |> Repo.all()
  end

  @doc "Returns all posted external_costs in a date range."
  def posted_costs(start_date, end_date) do
    ExternalCost
    |> where([c], not is_nil(c.posted_at))
    |> where([c], c.date >= ^start_date and c.date <= ^end_date)
    |> order_by([c], [desc: :date, asc: :service])
    |> Repo.all()
  end
end
