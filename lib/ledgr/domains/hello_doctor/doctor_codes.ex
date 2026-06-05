defmodule Ledgr.Domains.HelloDoctor.DoctorCodes do
  @moduledoc """
  Ledgr-side mirror of the bot's `app/services/doctor_codes.py` —
  generates `extension_code` + `referral_link` for doctors created
  via the Ledgr admin UI so they don't have to wait for the bot's
  next startup-time backfill to be patient-shareable.

  The format must match the bot's exactly so codes round-trip and
  the wa.me URL the bot sends matches the one Ledgr stores. Any
  drift here breaks the lookup the bot does when a patient sends
  `DR-XXXX` in WhatsApp.

  Match points:
    * Alphabet:  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/O/1/I/L)
    * Length:    4 chars
    * Public form: `DR-XXXX`
    * URL:       `https://wa.me/<number>?text=<quote(prefill)>` where
                 prefill = `"Hola, quiero una consulta médica. Mi doctor: DR-XXXX"`
                 and `quote` uses Python's `urllib.parse.quote` default-safe
                 set (alphanumerics + `_.-~/`).
    * Number:    `HELLO_DOCTOR_WHATSAPP_BUSINESS_NUMBER` env var, defaulting to
                 `5215614565790` (matches the bot's default in
                 `app/config.py:whatsapp_business_number`).

  If the env var is empty AND the default is cleared, `build_referral_link/1`
  returns `nil` — fail-safe, mirroring the bot.
  """

  import Ecto.Query, warn: false

  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_len 4
  @max_collision_retries 10
  @default_business_number "5215614565790"
  @referral_prefill_template "Hola, quiero una consulta médica. Mi doctor: ~s"

  @doc "Returns a fresh 4-char extension code not yet present in `doctors`."
  def generate_unique_code do
    Enum.reduce_while(1..@max_collision_retries, nil, fn _, _ ->
      code = random_code(@code_len)

      if code_in_use?(code) do
        {:cont, nil}
      else
        {:halt, code}
      end
    end)
    |> case do
      nil ->
        # 32^4 ≈ 1M codes — collisions this many times in a row is
        # astronomically unlikely. Fall back to 5 chars.
        Enum.reduce_while(1..@max_collision_retries, nil, fn _, _ ->
          code = random_code(@code_len + 1)
          if code_in_use?(code), do: {:cont, nil}, else: {:halt, code}
        end) ||
          raise "Unable to generate a unique extension code — alphabet exhausted"

      code ->
        code
    end
  end

  defp random_code(len) do
    alphabet_size = length(@alphabet)

    1..len
    |> Enum.map(fn _ ->
      :crypto.strong_rand_bytes(1)
      |> :binary.first()
      |> rem(alphabet_size)
      |> then(&Enum.at(@alphabet, &1))
    end)
    |> List.to_string()
  end

  defp code_in_use?(code) do
    Repo.exists?(from d in Doctor, where: d.extension_code == ^code)
  end

  @doc "Display form: `DR-XXXX`."
  def format_public(code) when is_binary(code), do: "DR-" <> String.upcase(code)

  @doc """
  Returns the `https://wa.me/...` deep link for `code`, or `nil` when
  `code` is falsy or the business number is unconfigured.
  """
  def build_referral_link(nil), do: nil
  def build_referral_link(""), do: nil

  def build_referral_link(code) when is_binary(code) do
    case business_number() do
      "" ->
        nil

      number ->
        prefill =
          :io_lib.format(@referral_prefill_template, [format_public(code)])
          |> IO.iodata_to_binary()

        "https://wa.me/#{number}?text=#{url_quote(prefill)}"
    end
  end

  defp business_number do
    (Application.get_env(:ledgr, :hello_doctor_whatsapp_business_number) ||
       @default_business_number)
    |> to_string()
    |> String.trim()
  end

  # Mirror Python's `urllib.parse.quote` with its default `safe="/"`:
  # the unreserved set per RFC 3986 (A-Z a-z 0-9 _.-~) PLUS the
  # forward slash. We don't have slashes in the prefill, so practically
  # this matches.  Built manually to avoid depending on a specific URI
  # encoding helper's exact behavior.
  defp url_quote(s) do
    s
    |> :binary.bin_to_list()
    |> Enum.map_join(&encode_byte/1)
  end

  defp encode_byte(b) when b in ?A..?Z, do: <<b>>
  defp encode_byte(b) when b in ?a..?z, do: <<b>>
  defp encode_byte(b) when b in ?0..?9, do: <<b>>
  defp encode_byte(b) when b in [?_, ?., ?-, ?~, ?/], do: <<b>>
  defp encode_byte(b), do: "%" <> (b |> Integer.to_string(16) |> String.pad_leading(2, "0"))

  @doc """
  Stamps a fresh `extension_code` + `referral_link` on a doctor when
  either is missing. Returns the (possibly updated) doctor.

  Idempotent — a row that already has both fields populated is
  returned unchanged. Doesn't raise on a write failure (logs +
  returns the un-updated row) since the doctor's main attributes
  are already saved and this is best-effort polish.
  """
  def stamp_missing!(%Doctor{} = doctor) do
    code = doctor.extension_code || generate_unique_code()
    link = doctor.referral_link || build_referral_link(code)

    cond do
      code == doctor.extension_code and link == doctor.referral_link ->
        doctor

      true ->
        attrs =
          %{}
          |> maybe_put(:extension_code, code, doctor.extension_code)
          |> maybe_put(:referral_link, link, doctor.referral_link)

        case Doctor.changeset(doctor, attrs) |> Repo.update() do
          {:ok, updated} ->
            updated

          {:error, changeset} ->
            require Logger

            Logger.warning(
              "[DoctorCodes] Failed to stamp #{doctor.id}: #{inspect(changeset.errors)}"
            )

            doctor
        end
    end
  end

  defp maybe_put(map, _key, value, value), do: map
  defp maybe_put(map, _key, nil, _existing), do: map
  defp maybe_put(map, key, value, _existing), do: Map.put(map, key, value)
end
