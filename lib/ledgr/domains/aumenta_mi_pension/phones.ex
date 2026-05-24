defmodule Ledgr.Domains.AumentaMiPension.Phones do
  @moduledoc """
  Phone-number normalizer for AMP leads.

  The three lead sources (`customers.phone`, `checkup_responses.contact_phone`,
  `calculadora_submissions.contact_phone`) store the same person's number
  in different shapes — some with country code (`5215522992238`), some
  without (`4442049782`), some with the Mexican mobile `1` prefix
  (`+52 1 55 …`). Direct string joins miss almost all real overlap.

  `normalize/1` collapses every recognizable variant to a single
  10-digit canonical Mexican-local key. We use the canonical form
  wherever we cross-join (Leads context, lead_crm overlay key, etc.)
  and leave the source-table values untouched (bot owns those columns).

  The two existing helpers in `Ledgr.Notifications.CallMeBot` and
  `Ledgr.Domains.AumentaMiPension.Agents.Agent` only strip non-digits;
  they don't unify country-code variants. Don't reuse — they're meant
  for different invariants (CallMeBot needs E.164, Agent normalizes
  for storage on writes).

  ## Examples

      iex> alias Ledgr.Domains.AumentaMiPension.Phones
      iex> Phones.normalize("+5215522992238")
      "5522992238"
      iex> Phones.normalize("525522992238")
      "5522992238"
      iex> Phones.normalize("4442049782")
      "4442049782"
      iex> Phones.normalize("(442) 204-9782")
      "4422049782"
      iex> Phones.normalize(nil)
      nil
      iex> Phones.normalize("")
      nil
      iex> Phones.normalize("123")
      nil
  """

  @doc """
  Normalize a phone string to 10-digit Mexican-local canonical form.

  Returns the canonical 10-digit string when input is recognizable,
  `nil` otherwise (including `nil` and empty input).
  """
  def normalize(nil), do: nil
  def normalize(""), do: nil

  def normalize(phone) when is_binary(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    cond do
      # +52 1 NN NNNN NNNN — Mexican mobile with country + mobile prefix.
      byte_size(digits) == 13 and String.starts_with?(digits, "521") ->
        String.slice(digits, 3, 10)

      # +52 NN NNNN NNNN — Mexican number with country code, no mobile prefix.
      byte_size(digits) == 12 and String.starts_with?(digits, "52") ->
        String.slice(digits, 2, 10)

      # Bare 10-digit local.
      byte_size(digits) == 10 ->
        digits

      true ->
        nil
    end
  end

  def normalize(_), do: nil
end
