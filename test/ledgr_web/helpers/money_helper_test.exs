defmodule LedgrWeb.Helpers.MoneyHelperTest do
  use ExUnit.Case, async: true

  alias LedgrWeb.Helpers.MoneyHelper

  # ---------------------------------------------------------------------------
  # pesos_to_cents/1
  # ---------------------------------------------------------------------------

  describe "pesos_to_cents/1" do
    test "returns 0 for nil" do
      assert MoneyHelper.pesos_to_cents(nil) == 0
    end

    test "returns 0 for empty string" do
      assert MoneyHelper.pesos_to_cents("") == 0
    end

    test "converts decimal string to cents" do
      assert MoneyHelper.pesos_to_cents("45.00") == 4500
      assert MoneyHelper.pesos_to_cents("1.50") == 150
      assert MoneyHelper.pesos_to_cents("100.99") == 10099
    end

    test "converts integer string to cents" do
      assert MoneyHelper.pesos_to_cents("100") == 10000
      assert MoneyHelper.pesos_to_cents("0") == 0
    end

    test "returns 0 for unparseable string" do
      assert MoneyHelper.pesos_to_cents("abc") == 0
      assert MoneyHelper.pesos_to_cents("$45") == 0
    end

    test "converts float to cents" do
      assert MoneyHelper.pesos_to_cents(45.0) == 4500
      assert MoneyHelper.pesos_to_cents(1.5) == 150
      assert MoneyHelper.pesos_to_cents(0.01) == 1
    end

    test "converts integer to cents (multiplies by 100)" do
      assert MoneyHelper.pesos_to_cents(100) == 10000
      assert MoneyHelper.pesos_to_cents(0) == 0
    end

    test "returns 0 for other types" do
      assert MoneyHelper.pesos_to_cents(:atoms_not_supported) == 0
      assert MoneyHelper.pesos_to_cents([]) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # cents_to_pesos/1
  # ---------------------------------------------------------------------------

  describe "cents_to_pesos/1" do
    test "returns 0.0 for nil" do
      assert MoneyHelper.cents_to_pesos(nil) == 0.0
    end

    test "converts cents integer to pesos float" do
      assert MoneyHelper.cents_to_pesos(4500) == 45.0
      assert MoneyHelper.cents_to_pesos(150) == 1.5
      assert MoneyHelper.cents_to_pesos(0) == 0.0
    end

    test "returns 0.0 for non-integer types" do
      assert MoneyHelper.cents_to_pesos("4500") == 0.0
      assert MoneyHelper.cents_to_pesos(45.0) == 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # format_price/1
  # ---------------------------------------------------------------------------

  describe "format_price/1" do
    test "returns empty string for nil" do
      assert MoneyHelper.format_price(nil) == ""
    end

    test "formats integer cents as MXN currency string" do
      assert MoneyHelper.format_price(4500) == "$45.00 MXN"
      assert MoneyHelper.format_price(150) == "$1.50 MXN"
      assert MoneyHelper.format_price(0) == "$0.00 MXN"
    end

    test "formats odd cent amounts correctly" do
      assert MoneyHelper.format_price(10099) == "$100.99 MXN"
      assert MoneyHelper.format_price(1) == "$0.01 MXN"
    end

    test "returns empty string for non-integer input" do
      assert MoneyHelper.format_price("4500") == ""
      assert MoneyHelper.format_price(45.0) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # convert_params_pesos_to_cents/2
  # ---------------------------------------------------------------------------

  describe "convert_params_pesos_to_cents/2" do
    test "converts string-keyed params" do
      params = %{"price_cents" => "45.00", "name" => "Product"}
      result = MoneyHelper.convert_params_pesos_to_cents(params, [:price_cents])
      assert result["price_cents"] == 4500
      assert result["name"] == "Product"
    end

    test "converts atom-keyed params" do
      params = %{price_cents: "100.00", name: "Product"}
      result = MoneyHelper.convert_params_pesos_to_cents(params, [:price_cents])
      assert result[:price_cents] == 10000
      assert result[:name] == "Product"
    end

    test "converts multiple fields" do
      params = %{"unit_cost_cents" => "10.00", "total_cost_cents" => "50.00"}

      result =
        MoneyHelper.convert_params_pesos_to_cents(params, [:unit_cost_cents, :total_cost_cents])

      assert result["unit_cost_cents"] == 1000
      assert result["total_cost_cents"] == 5000
    end

    test "skips fields not present in the map" do
      params = %{"name" => "Widget"}
      result = MoneyHelper.convert_params_pesos_to_cents(params, [:price_cents])
      assert result == %{"name" => "Widget"}
    end

    test "returns params unchanged when not a map" do
      assert MoneyHelper.convert_params_pesos_to_cents("not_a_map", [:price_cents]) == "not_a_map"
    end
  end

  # ---------------------------------------------------------------------------
  # convert_nested_params_pesos_to_cents/3
  # ---------------------------------------------------------------------------

  describe "convert_nested_params_pesos_to_cents/3" do
    test "converts nested map value with string key" do
      params = %{
        "journal_entry" => %{"amount_cents" => "99.00"}
      }

      result =
        MoneyHelper.convert_nested_params_pesos_to_cents(params, :journal_entry, [:amount_cents])

      assert result["journal_entry"]["amount_cents"] == 9900
    end

    test "converts nested list of maps with string key" do
      params = %{
        "journal_lines" => [
          %{"amount_cents" => "10.00"},
          %{"amount_cents" => "20.00"}
        ]
      }

      result =
        MoneyHelper.convert_nested_params_pesos_to_cents(params, :journal_lines, [:amount_cents])

      [line1, line2] = result["journal_lines"]
      assert line1["amount_cents"] == 1000
      assert line2["amount_cents"] == 2000
    end

    test "converts nested map value with atom key" do
      params = %{
        journal_lines: [%{"debit_cents" => "5.00"}]
      }

      result =
        MoneyHelper.convert_nested_params_pesos_to_cents(params, :journal_lines, [:debit_cents])

      [line] = result[:journal_lines]
      assert line["debit_cents"] == 500
    end

    test "returns params unchanged when nested key is absent" do
      params = %{"name" => "test"}

      result =
        MoneyHelper.convert_nested_params_pesos_to_cents(params, :journal_lines, [:amount_cents])

      assert result == params
    end

    test "returns params unchanged when not a map" do
      assert MoneyHelper.convert_nested_params_pesos_to_cents("not_a_map", :key, [:field]) ==
               "not_a_map"
    end

    test "leaves non-map items in list unchanged" do
      params = %{"lines" => ["string_item"]}
      result = MoneyHelper.convert_nested_params_pesos_to_cents(params, :lines, [:amount_cents])
      assert result["lines"] == ["string_item"]
    end
  end
end
