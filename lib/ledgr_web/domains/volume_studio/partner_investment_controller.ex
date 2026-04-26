defmodule LedgrWeb.Domains.VolumeStudio.PartnerInvestmentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.PartnerInvestments
  alias Ledgr.Core.Accounting

  def index(conn, _params) do
    summaries = PartnerInvestments.partner_summaries()
    activity = PartnerInvestments.list_activity(limit: 50)
    total_net_cents = PartnerInvestments.total_net_cents()
    equity_summary = Accounting.get_equity_summary()

    render(conn, :index,
      summaries: summaries,
      activity: activity,
      total_net_cents: total_net_cents,
      equity_summary: equity_summary
    )
  end
end

defmodule LedgrWeb.Domains.VolumeStudio.PartnerInvestmentHTML do
  use LedgrWeb, :html

  embed_templates "partner_investment_html/*"

  def fmt_short_date(nil), do: "—"
  def fmt_short_date(%Date{} = d), do: Calendar.strftime(d, "%b %d, %Y")

  def direction_label("in"), do: {"Contribution", "status-paid"}
  def direction_label("out"), do: {"Withdrawal", "status-unpaid"}
  def direction_label(_), do: {"—", ""}
end
