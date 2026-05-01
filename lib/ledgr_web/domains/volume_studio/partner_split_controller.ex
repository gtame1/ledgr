defmodule LedgrWeb.Domains.VolumeStudio.PartnerSplitController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.PartnerSplits
  alias Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplit
  alias Ledgr.Core.Partners

  def index(conn, _params) do
    splits = PartnerSplits.list_partner_splits()
    render(conn, :index, splits: splits)
  end

  def new(conn, _params) do
    blank = %PartnerSplit{lines: [empty_line(), empty_line()]}
    changeset = PartnerSplits.change_partner_split(blank)

    render(conn, :new,
      changeset: changeset,
      partner_options: partner_options(),
      action: dp(conn, "/partner-splits")
    )
  end

  def create(conn, %{"partner_split" => params}) do
    case PartnerSplits.create_partner_split(params) do
      {:ok, _split} ->
        conn
        |> put_flash(:info, "Partner split created.")
        |> redirect(to: dp(conn, "/partner-splits"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          changeset: changeset,
          partner_options: partner_options(),
          action: dp(conn, "/partner-splits")
        )
    end
  end

  def edit(conn, %{"id" => id}) do
    split = PartnerSplits.get_partner_split!(id)
    changeset = PartnerSplits.change_partner_split(split)

    render(conn, :edit,
      split: split,
      changeset: changeset,
      partner_options: partner_options(),
      action: dp(conn, "/partner-splits/#{id}")
    )
  end

  def update(conn, %{"id" => id, "partner_split" => params}) do
    split = PartnerSplits.get_partner_split!(id)

    case PartnerSplits.update_partner_split(split, params) do
      {:ok, _split} ->
        conn
        |> put_flash(:info, "Partner split updated.")
        |> redirect(to: dp(conn, "/partner-splits"))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          split: split,
          changeset: changeset,
          partner_options: partner_options(),
          action: dp(conn, "/partner-splits/#{id}")
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    split = PartnerSplits.get_partner_split!(id)
    {:ok, _} = PartnerSplits.soft_delete_partner_split(split)

    conn
    |> put_flash(:info, "Partner split removed.")
    |> redirect(to: dp(conn, "/partner-splits"))
  end

  # ── Expense attribution ─────────────────────────────────────────────

  def expenses(conn, _params) do
    expenses = Ledgr.Core.Expenses.list_expenses() |> Enum.take(100)
    expense_ids = Enum.map(expenses, & &1.id)
    assignments = PartnerSplits.split_ids_for_expenses(expense_ids)

    render(conn, :expenses,
      expenses: expenses,
      assignments: assignments,
      split_options: PartnerSplits.split_options()
    )
  end

  def breakdown(conn, params) do
    today = LedgrWeb.Helpers.DomainHelpers.today_mx()
    {start_date, end_date} = parse_date_range(params, today)

    breakdown = PartnerSplits.partner_breakdown(start_date, end_date)

    render(conn, :breakdown,
      breakdown: breakdown,
      start_date: start_date,
      end_date: end_date
    )
  end

  defp parse_date_range(params, today) do
    s =
      case Date.from_iso8601(params["start_date"] || "") do
        {:ok, d} -> d
        _ -> Date.beginning_of_month(today)
      end

    e =
      case Date.from_iso8601(params["end_date"] || "") do
        {:ok, d} -> d
        _ -> Date.end_of_month(today)
      end

    {s, e}
  end

  def assign_expense(conn, %{"expense_id" => expense_id, "partner_split_id" => split_id}) do
    expense_id = String.to_integer(expense_id)

    split_id =
      case split_id do
        "" -> nil
        nil -> nil
        v -> String.to_integer(v)
      end

    case PartnerSplits.set_expense_split(expense_id, split_id) do
      :ok ->
        conn
        |> put_flash(:info, "Expense attribution cleared.")
        |> redirect(to: dp(conn, "/partner-splits/expenses"))

      {:ok, _} ->
        conn
        |> put_flash(:info, "Expense attribution updated.")
        |> redirect(to: dp(conn, "/partner-splits/expenses"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not save attribution.")
        |> redirect(to: dp(conn, "/partner-splits/expenses"))
    end
  end

  defp partner_options do
    Partners.list_partners()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp empty_line, do: %Ledgr.Domains.VolumeStudio.PartnerSplits.PartnerSplitLine{}
end

defmodule LedgrWeb.Domains.VolumeStudio.PartnerSplitHTML do
  use LedgrWeb, :html

  embed_templates "partner_split_html/*"

  @doc "Formats basis points (e.g. 2500 → \"25%\", 3333 → \"33.33%\")."
  def fmt_bps(nil), do: "—"

  def fmt_bps(bps) when is_integer(bps) do
    pct = bps / 100

    if pct == Float.round(pct) do
      "#{trunc(pct)}%"
    else
      "#{:erlang.float_to_binary(pct, decimals: 2)}%"
    end
  end

  @doc """
  Returns the share-percent value to render in a line form input.

  Prefers the value the user just typed (in form params), then falls back to
  share_bps from the changeset's data, otherwise blank.
  """
  def share_pct_value(line_form) do
    cond do
      pct = Phoenix.HTML.Form.input_value(line_form, :share_pct) ->
        pct

      bps = Phoenix.HTML.Form.input_value(line_form, :share_bps) ->
        :erlang.float_to_binary(bps / 100, decimals: 2)

      true ->
        ""
    end
  end
end
