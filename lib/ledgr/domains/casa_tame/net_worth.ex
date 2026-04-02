defmodule Ledgr.Domains.CasaTame.NetWorth do
  @moduledoc """
  Calculates unified net worth entirely from the chart of accounts (ledger).

  Combines:
  - Cash & bank accounts (asset codes 1000-1049, 1100-1149)
  - Investment accounts (asset codes 1050-1099)
  - Fixed assets (asset codes 1150-1199)
  - Liabilities (codes 2000-2199)

  Uses the cached exchange rate to convert between USD and MXN.
  """

  alias Ledgr.Core.Accounting
  alias Ledgr.Domains.CasaTame.ExchangeRates

  def calculate do
    rate = ExchangeRates.usd_to_mxn_rate()
    balance_sheet = Accounting.balance_sheet(Ledgr.Domains.CasaTame.today())

    # Categorize assets by code range
    {cash_usd, cash_mxn, investments_usd, fixed_mxn} =
      Enum.reduce(balance_sheet.assets, {0, 0, 0, 0}, fn item, {cu, cm, iu, fm} ->
        code = item.account.code
        amt = item.amount_cents

        cond do
          code >= "1000" and code < "1050" -> {cu + amt, cm, iu, fm}
          code >= "1050" and code < "1100" -> {cu, cm, iu + amt, fm}
          code >= "1100" and code < "1150" -> {cu, cm + amt, iu, fm}
          code >= "1150" and code < "1200" -> {cu, cm, iu, fm + amt}
          true -> {cu, cm, iu, fm}
        end
      end)

    # Categorize liabilities by code range
    {liabilities_usd, liabilities_mxn} =
      Enum.reduce(balance_sheet.liabilities, {0, 0}, fn item, {lu, lm} ->
        code = item.account.code

        cond do
          code >= "2000" and code < "2100" -> {lu + item.amount_cents, lm}
          code >= "2100" and code < "2200" -> {lu, lm + item.amount_cents}
          true -> {lu, lm}
        end
      end)

    accounts_usd = cash_usd + investments_usd
    accounts_mxn = cash_mxn + fixed_mxn

    net_usd = accounts_usd - liabilities_usd
    net_mxn = accounts_mxn - liabilities_mxn

    # Convert to unified totals
    total_mxn = net_mxn + round(net_usd * rate)
    total_usd = round(net_mxn / max(rate, 0.01)) + net_usd

    %{
      rate: rate,
      # USD breakdown
      cash_usd: cash_usd,
      investments_usd: investments_usd,
      accounts_usd: accounts_usd,
      liabilities_usd: liabilities_usd,
      net_usd: net_usd,
      # MXN breakdown
      cash_mxn: cash_mxn,
      fixed_mxn: fixed_mxn,
      accounts_mxn: accounts_mxn,
      liabilities_mxn: liabilities_mxn,
      net_mxn: net_mxn,
      # Unified
      total_mxn: total_mxn,
      total_usd: total_usd
    }
  end
end
