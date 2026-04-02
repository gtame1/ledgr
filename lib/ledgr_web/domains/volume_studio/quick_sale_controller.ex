defmodule LedgrWeb.Domains.VolumeStudio.QuickSaleController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.VolumeStudio.SubscriptionPlans
  alias Ledgr.Domains.VolumeStudio.Subscriptions
  alias Ledgr.Core.Customers
  alias Ledgr.Core.Customers.Customer

  # ── GET /quick-sale/new ────────────────────────────────────────────────

  def new(conn, params) do
    preselected_customer_id = params["customer_id"]
    mode      = Map.get(params, "mode", "existing")
    plans     = SubscriptionPlans.list_active_extra_plans()
    customers = customer_options()

    render(conn, :new,
      plans:                   plans,
      customers:               customers,
      customer_changeset:      Customers.change_customer(%Customer{}),
      mode:                    mode,
      preselected_customer_id: preselected_customer_id,
      today:                   today_mx() |> Date.to_iso8601(),
      action:                  dp(conn, "/quick-sale")
    )
  end

  # ── POST /quick-sale ───────────────────────────────────────────────────

  def create(conn, %{"quick_sale" => p}) do
    today              = today_mx()
    sale_date          = parse_date(p["sale_date"]) || today
    discount           = parse_int(p["discount_cents"])
    mode               = Map.get(p, "mode", "existing")
    new_customer_params = Map.get(p, "new_customer", %{})

    # Resolve customer_id: create new customer first if needed
    customer_result =
      if mode == "new" do
        case Customers.create_customer(new_customer_params) do
          {:ok, customer} -> {:ok, customer.id}
          {:error, cs}    -> {:error, :customer, cs}
        end
      else
        {:ok, p["customer_id"]}
      end

    case customer_result do
      {:ok, customer_id} ->
        sub_attrs = %{
          "customer_id"          => customer_id,
          "subscription_plan_id" => p["subscription_plan_id"],
          "starts_on"            => sale_date,
          "ends_on"              => sale_date,
          "status"               => "active",
          "discount_cents"       => discount
        }

        case Subscriptions.create_subscription(sub_attrs) do
          {:ok, sub} ->
            conn
            |> put_flash(:info, "Sale created. Record payment whenever you're ready.")
            |> redirect(to: dp(conn, "/subscriptions/#{sub.id}"))

          {:error, changeset} ->
            conn
            |> put_flash(:error, "Could not save — please check the form.")
            |> render(:new,
                plans:                   SubscriptionPlans.list_active_extra_plans(),
                customers:               customer_options(),
                customer_changeset:      Customers.change_customer(%Customer{}),
                mode:                    mode,
                preselected_customer_id: nil,
                today:                   Date.to_iso8601(today),
                action:                  dp(conn, "/quick-sale"),
                changeset:               changeset)
        end

      {:error, :customer, customer_changeset} ->
        conn
        |> put_flash(:error, "Could not create member — please check the form.")
        |> render(:new,
            plans:                   SubscriptionPlans.list_active_extra_plans(),
            customers:               customer_options(),
            customer_changeset:      customer_changeset,
            mode:                    "new",
            preselected_customer_id: nil,
            today:                   Date.to_iso8601(today),
            action:                  dp(conn, "/quick-sale"))
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp customer_options do
    Customers.list_customers()
    |> Enum.map(&{"#{&1.name} (#{&1.phone})", &1.id})
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp parse_int(n) when is_integer(n), do: n
  defp parse_int(_), do: 0
end
