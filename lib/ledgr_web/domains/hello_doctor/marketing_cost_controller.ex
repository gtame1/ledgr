defmodule LedgrWeb.Domains.HelloDoctor.MarketingCostController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.MarketingCosts.MarketingCost
  alias Ledgr.Domains.HelloDoctor.MarketingCostAccounting
  alias Ledgr.Domains.HelloDoctor.MarketingCostImport
  alias Ledgr.Repo

  def index(conn, _params) do
    costs = MarketingCostAccounting.list_all()
    render(conn, :index, costs: costs, summary: summarize(costs))
  end

  def bulk_upload_form(conn, _params) do
    render(conn, :bulk_upload, errors: nil, rows: nil, restatements: nil)
  end

  def bulk_upload_submit(conn, %{"upload" => %{"file" => %Plug.Upload{path: path}}}) do
    csv = File.read!(path)

    case MarketingCostImport.parse(csv) do
      {:ok, %{rows: rows, restatements: restatements, skipped: skipped} = parsed} ->
        # Idempotent: inserts use on_conflict: :nothing, and each restatement's
        # UPDATE is guarded on the amount it was computed from.
        {:ok, %{inserted: inserted, restated: restated}} = MarketingCostImport.commit(parsed)

        already = skipped + (length(rows) - inserted) + (length(restatements) - restated)

        conn
        |> put_flash(:info, upload_summary(inserted, restated, already))
        |> redirect(to: dp(conn, "/marketing-costs"))

      {:error, %{rows: rows, restatements: restatements, errors: errors}} ->
        conn
        |> put_flash(:error, "CSV has #{length(errors)} issue(s). Nothing was saved.")
        |> render(:bulk_upload, errors: errors, rows: rows, restatements: restatements)
    end
  end

  def bulk_upload_submit(conn, _params) do
    conn
    |> put_flash(:error, "Please choose a CSV file to upload.")
    |> redirect(to: dp(conn, "/marketing-costs/bulk-upload"))
  end

  # Restated charges are called out separately: an upload that silently revises
  # figures already in the ledger is exactly what you want to notice.
  defp upload_summary(0, 0, _already),
    do: "No changes — everything in this file was already imported."

  defp upload_summary(inserted, restated, already) do
    [
      if(inserted > 0, do: "Imported #{inserted} new charge(s)"),
      if(restated > 0,
        do: "restated #{restated} charge(s) whose amount changed (GL adjusted)"
      ),
      if(already > 0, do: "#{already} already up to date")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> Kernel.<>(".")
  end

  @doc "A blank CSV template with the expected header + an example row."
  def bulk_template(conn, _params) do
    today = Ledgr.Domains.HelloDoctor.today()

    csv =
      [
        ["date", "platform", "amount", "currency", "description"],
        [to_string(today), "meta", "0.00", "MXN", "Meta ad spend"],
        [to_string(today), "google", "0.00", "MXN", "Google Ads spend"]
      ]
      |> Enum.map_join("", fn row -> Enum.join(row, ",") <> "\r\n" end)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="marketing-costs-template.csv")
    )
    |> send_resp(200, csv)
  end

  def delete(conn, %{"id" => id}) do
    cost = Repo.get!(MarketingCost, id)

    case MarketingCostAccounting.delete_cost(cost) do
      {:ok, _} ->
        conn
        |> put_flash(
          :info,
          "Deleted #{cost.platform} spend for #{cost.date} (GL reversed if it was posted)."
        )
        |> redirect(to: dp(conn, "/marketing-costs"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Couldn't delete: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/marketing-costs"))
    end
  end

  # Total + per-platform + per-month MXN summary for the KPI cards.
  defp summarize(costs) do
    total = Enum.reduce(costs, 0, fn c, acc -> acc + mxn_cents(c) end)

    by_platform =
      costs
      |> Enum.group_by(& &1.platform)
      |> Enum.map(fn {p, rows} -> {p, Enum.reduce(rows, 0, fn c, a -> a + mxn_cents(c) end)} end)
      |> Enum.sort_by(fn {_p, cents} -> -cents end)

    %{total_mxn: total / 100.0, by_platform: by_platform, count: length(costs)}
  end

  # Posted rows carry spend_mxn_cents; unposted MXN rows fall back to amount.
  defp mxn_cents(%MarketingCost{spend_mxn_cents: c}) when is_integer(c), do: c
  defp mxn_cents(%MarketingCost{amount: a, currency: "MXN"}) when is_number(a), do: round(a * 100)
  defp mxn_cents(_), do: 0
end

defmodule LedgrWeb.Domains.HelloDoctor.MarketingCostHTML do
  use LedgrWeb, :html

  embed_templates "marketing_cost_html/*"

  @doc "MXN pesos string for a cost row (posted cents, else MXN amount)."
  def cost_mxn(%{spend_mxn_cents: c}) when is_integer(c), do: fmt_money(c / 100.0)
  def cost_mxn(%{amount: a, currency: "MXN"}) when is_number(a), do: fmt_money(a)
  def cost_mxn(_), do: "—"

  # Credits are negative; render them as "-$12.34" rather than "$-12.34".
  def fmt_money(n) when is_number(n) and n < 0,
    do: "-$#{:erlang.float_to_binary(abs(n) / 1, decimals: 2)}"

  def fmt_money(n) when is_number(n), do: "$#{:erlang.float_to_binary(n / 1, decimals: 2)}"
  def fmt_money(_), do: "$0.00"

  def platform_label("meta"), do: "Meta"
  def platform_label("google"), do: "Google Ads"
  def platform_label("google_ads"), do: "Google Ads"
  def platform_label(other) when is_binary(other), do: String.capitalize(other)
  def platform_label(_), do: "—"
end
