defmodule Ledgr.Core.Partners do
  @moduledoc """
  Partners and capital contributions (investments).
  """

  import Ecto.Query
  alias Ledgr.Repo

  alias __MODULE__.{Partner, CapitalContribution}
  alias Ledgr.Core.Accounting

  # ---------- Form changeset for UI (amount in pesos) ----------

  def change_contribution_form(attrs \\ %{}) do
    {%{
       partner_id: nil,
       cash_account_id: nil,
       date: LedgrWeb.Helpers.DomainHelpers.today_mx(),
       amount_pesos: nil,
       note: nil
     },
     %{
       partner_id: :integer,
       cash_account_id: :integer,
       date: :date,
       amount_pesos: :decimal,
       note: :string
     }}
    |> Ecto.Changeset.cast(attrs, [:partner_id, :cash_account_id, :date, :amount_pesos, :note])
    |> Ecto.Changeset.validate_required([:partner_id, :cash_account_id, :date, :amount_pesos])
    |> Ecto.Changeset.validate_number(:amount_pesos, greater_than: 0)
  end

  @doc """
  Creates a capital contribution and records accounting entry
  (Debit Cash, Credit Owner's Equity).
  """
  def create_contribution(attrs) do
    form_changeset = change_contribution_form(attrs)

    if form_changeset.valid? do
      %{
        partner_id: partner_id,
        cash_account_id: cash_account_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        contribution_changeset =
          CapitalContribution.changeset(%CapitalContribution{}, %{
            partner_id: partner_id,
            cash_account_id: cash_account_id,
            date: date,
            amount_cents: amount_cents,
            note: note
          })

        contribution = Repo.insert!(contribution_changeset)

        partner = Repo.get!(Partner, partner_id)

        Accounting.record_investment(
          amount_cents,
          date: date,
          partner_name: partner.name,
          cash_account_id: cash_account_id
        )

        contribution
      end)
      |> case do
        {:ok, contribution} ->
          {:ok, contribution}

        {:error, reason} ->
          {:error,
           form_changeset
           |> Ecto.Changeset.add_error(:base, "Failed to save contribution: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  def create_withdrawal(attrs) do
    form_changeset = change_contribution_form(attrs)

    if form_changeset.valid? do
      %{
        partner_id: partner_id,
        cash_account_id: cash_account_id,
        date: date,
        amount_pesos: amount_pesos,
        note: note
      } = Ecto.Changeset.apply_changes(form_changeset)

      amount_cents =
        amount_pesos
        # POSITIVE
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      Repo.transaction(fn ->
        contribution_changeset =
          CapitalContribution.changeset(%CapitalContribution{}, %{
            partner_id: partner_id,
            cash_account_id: cash_account_id,
            date: date,
            amount_cents: amount_cents,
            note: note,
            direction: "out"
          })

        contribution = Repo.insert!(contribution_changeset)

        partner = Repo.get!(Partner, partner_id)

        Accounting.record_withdrawal(amount_cents,
          date: date,
          partner_name: partner.name,
          cash_account_id: cash_account_id
        )

        contribution
      end)
      |> case do
        {:ok, contribution} ->
          {:ok, contribution}

        {:error, reason} ->
          {:error,
           form_changeset
           |> Ecto.Changeset.add_error(:base, "Failed to save withdrawal: #{inspect(reason)}")}
      end
    else
      {:error, form_changeset}
    end
  end

  # ---------- Queries for dashboard ----------

  def list_partners_with_totals do
    from(p in Partner,
      left_join: c in CapitalContribution,
      on: c.partner_id == p.id,
      group_by: [p.id],
      select: %{
        partner: p,
        total_cents:
          coalesce(
            sum(
              fragment(
                "CASE WHEN ? = 'out' THEN -? ELSE ? END",
                c.direction,
                c.amount_cents,
                c.amount_cents
              )
            ),
            0
          )
      }
    )
    |> Repo.all()
  end

  def total_invested_cents do
    from(c in CapitalContribution,
      select:
        coalesce(
          sum(
            fragment(
              "CASE WHEN ? = 'out' THEN -? ELSE ? END",
              c.direction,
              c.amount_cents,
              c.amount_cents
            )
          ),
          0
        )
    )
    |> Repo.one()
  end

  def list_recent_contributions(limit \\ 10) do
    CapitalContribution
    |> order_by(desc: :date, desc: :inserted_at)
    |> preload(:partner)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_partners do
    Repo.all(Partner)
  end

  def partner_select_options do
    list_partners()
    |> Enum.map(&{&1.name, &1.id})
  end
end
