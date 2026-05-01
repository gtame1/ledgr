defmodule LedgrWeb.Helpers.MoneyHelper do
  @moduledoc """
  Helper functions for converting between pesos and cents for form inputs.
  """

  @doc """
  Converts pesos (decimal/float) to cents (integer).
  Handles strings, floats, and integers.
  """
  def pesos_to_cents(nil), do: 0
  def pesos_to_cents(""), do: 0

  def pesos_to_cents(value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, _} -> round(float_value * 100)
      :error -> 0
    end
  end

  def pesos_to_cents(value) when is_float(value), do: round(value * 100)
  def pesos_to_cents(value) when is_integer(value), do: value * 100
  def pesos_to_cents(_), do: 0

  @doc """
  Converts cents (integer) to pesos (float) for display in forms.
  """
  def cents_to_pesos(nil), do: 0.0
  def cents_to_pesos(cents) when is_integer(cents), do: cents / 100.0
  def cents_to_pesos(_), do: 0.0

  @doc """
  Formats cents as a MXN currency string (e.g. "$45.00 MXN").
  """
  def format_price(nil), do: ""

  def format_price(cents) when is_integer(cents) do
    pesos = cents / 100
    "$#{:erlang.float_to_binary(pesos, decimals: 2)} MXN"
  end

  def format_price(_), do: ""

  @doc """
  Converts a map of params, converting all fields ending in _cents from pesos to cents.
  """
  def convert_params_pesos_to_cents(params, fields) when is_map(params) do
    Enum.reduce(fields, params, fn field, acc ->
      field_str = to_string(field)

      # Try both string and atom keys
      value =
        cond do
          Map.has_key?(acc, field_str) -> Map.get(acc, field_str)
          Map.has_key?(acc, field) -> Map.get(acc, field)
          true -> nil
        end

      if value != nil do
        cents_value = pesos_to_cents(value)
        # Update both string and atom keys if they exist
        acc
        |> Map.put(field_str, cents_value)
        |> (fn map ->
              if Map.has_key?(map, field), do: Map.put(map, field, cents_value), else: map
            end).()
      else
        acc
      end
    end)
  end

  def convert_params_pesos_to_cents(params, _fields), do: params

  @doc """
  Converts nested params (like journal_lines) from pesos to cents.
  Handles both list and map formats.
  """
  def convert_nested_params_pesos_to_cents(params, nested_key, fields) when is_map(params) do
    nested_key_str = to_string(nested_key)

    cond do
      Map.has_key?(params, nested_key_str) ->
        nested = params[nested_key_str]
        updated_nested = convert_nested_value(nested, fields)
        Map.put(params, nested_key_str, updated_nested)

      Map.has_key?(params, nested_key) ->
        nested = params[nested_key]
        updated_nested = convert_nested_value(nested, fields)
        Map.put(params, nested_key, updated_nested)

      true ->
        params
    end
  end

  def convert_nested_params_pesos_to_cents(params, _nested_key, _fields), do: params

  defp convert_nested_value(nested, fields) when is_map(nested) do
    # Single nested object
    convert_params_pesos_to_cents(nested, fields)
  end

  defp convert_nested_value(nested, fields) when is_list(nested) do
    # List of nested objects (like journal_lines array)
    Enum.map(nested, fn item ->
      if is_map(item) do
        convert_params_pesos_to_cents(item, fields)
      else
        item
      end
    end)
  end

  defp convert_nested_value(nested, _fields), do: nested
end
