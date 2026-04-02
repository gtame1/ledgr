defmodule Ledgr.Domains.MrMunchMe.Orders do
  import Ecto.Query, warn: false
  alias Ledgr.Repo

  alias Ledgr.Domains.MrMunchMe.Orders.{Order, Product, ProductImage, ProductVariant, OrderPayment, OrderIngredient, DiscountCode}
  alias Ledgr.Domains.MrMunchMe.{OrderAccounting, PendingCheckout}
  alias Ledgr.Domains.MrMunchMe.Inventory.Location
  alias Ledgr.Core.{Customers, Accounting}
  alias Ledgr.Repo


  # PRODUCTS

  def list_products do
    Repo.all(from p in Product, where: p.active == true and is_nil(p.deleted_at), order_by: [asc: p.position, asc: p.name])
  end

  def list_products_filtered(params \\ %{}) do
    Product
    |> where([p], p.active == true and is_nil(p.deleted_at))
    |> maybe_search_products(params["q"])
    |> order_by([p], [asc: p.position, asc: p.name])
    |> Repo.all()
  end

  defp maybe_search_products(query, nil), do: query
  defp maybe_search_products(query, ""), do: query

  defp maybe_search_products(query, term) do
    search = "%#{term}%"
    from p in query, where: ilike(p.name, ^search) or ilike(p.description, ^search)
  end

  def list_all_products do
    from(p in Product, where: is_nil(p.deleted_at), order_by: [asc: p.position, asc: p.name], preload: :variants)
    |> Repo.all()
  end

  def get_product!(id) do
    from(p in Product, where: p.id == ^id and is_nil(p.deleted_at))
    |> Repo.one!()
  end

  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  def create_product(attrs) do
    next_position =
      (Repo.one(from p in Product, where: is_nil(p.deleted_at), select: max(p.position)) || -1) + 1

    %Product{}
    |> Product.changeset(attrs)
    |> Ecto.Changeset.put_change(:position, next_position)
    |> Repo.insert()
  end

  def move_product_up(%Product{} = product) do
    all = Repo.all(from p in Product, where: is_nil(p.deleted_at), order_by: [asc: p.position, asc: p.name])
    idx = Enum.find_index(all, &(&1.id == product.id))

    if idx && idx > 0 do
      swap_product_positions(product, Enum.at(all, idx - 1))
    else
      {:ok, product}
    end
  end

  def move_product_down(%Product{} = product) do
    all = Repo.all(from p in Product, where: is_nil(p.deleted_at), order_by: [asc: p.position, asc: p.name])
    idx = Enum.find_index(all, &(&1.id == product.id))

    if idx && idx < length(all) - 1 do
      swap_product_positions(product, Enum.at(all, idx + 1))
    else
      {:ok, product}
    end
  end

  defp swap_product_positions(a, b) do
    pos_a = a.position
    pos_b = if b.position == a.position, do: a.position + 1, else: b.position

    Repo.transaction(fn ->
      Repo.update!(Ecto.Changeset.change(a, position: pos_b))
      Repo.update!(Ecto.Changeset.change(b, position: pos_a))
    end)
  end

  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(%Product{} = product) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      from(v in ProductVariant, where: v.product_id == ^product.id)
      |> Repo.update_all(set: [deleted_at: now, updated_at: now])

      product |> Ecto.Changeset.change(deleted_at: now) |> Repo.update!()
    end)
  end

  def get_product_with_images!(id) do
    from(p in Product, where: p.id == ^id and is_nil(p.deleted_at))
    |> Repo.one!()
    |> Repo.preload([
      :images,
      variants: from(v in ProductVariant, where: is_nil(v.deleted_at), order_by: v.name)
    ])
  end

  def list_products_with_variants do
    from(p in Product,
      where: p.active == true and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name],
      preload: [
        variants:
          ^from(v in ProductVariant, where: v.active == true and is_nil(v.deleted_at), order_by: v.name)
      ]
    )
    |> Repo.all()
  end

  # PRODUCT IMAGES (Gallery)

  def list_product_images(product_id) do
    Repo.all(
      from pi in ProductImage,
        where: pi.product_id == ^product_id,
        order_by: [asc: pi.position]
    )
  end

  def get_product_image!(id), do: Repo.get!(ProductImage, id)

  def create_product_image(attrs) do
    %ProductImage{}
    |> ProductImage.changeset(attrs)
    |> Repo.insert()
  end

  def delete_product_image(%ProductImage{} = image) do
    # Delete the file from disk if it's a local upload
    Ledgr.Uploads.delete(image.image_url)
    Repo.delete(image)
  end

  def product_select_options do
    list_products()
    |> Enum.map(fn p -> {p.name, p.id} end)
  end

  @doc """
  Returns select options grouped by product for all active variants.
  Each entry is `{"Product · Variant (SKU)", variant_id}`.
  Used in admin order forms so operators pick the specific size.
  """
  def variant_select_options do
    from(v in ProductVariant,
      join: p in assoc(v, :product),
      where: v.active == true and p.active == true and is_nil(v.deleted_at) and is_nil(p.deleted_at),
      order_by: [p.name, v.name],
      select: {v.id, p.name, v.name, v.sku}
    )
    |> Repo.all()
    |> Enum.map(fn {id, product_name, variant_name, sku} ->
      label =
        if sku do
          "#{product_name} · #{variant_name} (#{sku})"
        else
          "#{product_name} · #{variant_name}"
        end

      {label, id}
    end)
  end

  # VARIANT CRUD

  def get_variant!(id) do
    from(v in ProductVariant, where: v.id == ^id and is_nil(v.deleted_at))
    |> Repo.one!()
    |> Repo.preload(:product)
  end

  def list_variants_for_product(%Product{} = product) do
    from(v in ProductVariant,
      where: v.product_id == ^product.id and is_nil(v.deleted_at),
      order_by: v.name
    )
    |> Repo.all()
  end

  def list_active_variants do
    from(v in ProductVariant,
      where: v.active == true and is_nil(v.deleted_at),
      order_by: v.name
    )
    |> Repo.all()
  end

  @doc """
  List all active variants whose parent product is also active,
  ordered by product name then variant name, with product preloaded.
  Used by the recipe index to detect variants missing a recipe.
  """
  def list_all_active_variants_with_products do
    from(v in ProductVariant,
      join: p in assoc(v, :product),
      where: v.active == true and p.active == true and is_nil(v.deleted_at) and is_nil(p.deleted_at),
      order_by: [p.name, v.name],
      preload: [product: p]
    )
    |> Repo.all()
  end

  def create_variant(attrs) do
    %ProductVariant{}
    |> ProductVariant.changeset(attrs)
    |> Repo.insert()
  end

  def update_variant(%ProductVariant{} = variant, attrs) do
    variant
    |> ProductVariant.changeset(attrs)
    |> Repo.update()
  end

  def delete_variant(%ProductVariant{} = variant) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    variant |> Ecto.Changeset.change(deleted_at: now) |> Repo.update()
  end

  # ORDERS

  def list_orders(params \\ %{}) do
    import Ecto.Query

    base_query =
      from o in Order,
        as: :order,
        join: v in assoc(o, :variant),
        as: :variant,
        join: p in assoc(v, :product),
        as: :product,
        join: l in assoc(o, :prep_location),
        as: :prep_location,
        left_join: c in assoc(o, :customer),
        as: :customer,
        preload: [:order_payments, variant: {v, product: p}, prep_location: l, customer: c]

    # Exclude canceled orders by default unless explicitly filtering for canceled status
    query =
      if params["status"] == "canceled" do
    base_query
      else
        from o in base_query, where: o.status != "canceled"
      end

    query
    |> maybe_filter_status(params["status"])
    |> maybe_filter_delivery_type(params["delivery_type"])
    |> maybe_filter_date_range(params["date_from"], params["date_to"])
    |> maybe_filter_product_id(params["product_id"])
    |> maybe_filter_prep_location(params["prep_location_id"])
    |> apply_sort(params["sort_by"], params["sort_dir"])
    |> Repo.all()
  end

  def list_canceled_orders(limit \\ 50, offset \\ 0) do
    import Ecto.Query

    canceled_orders =
      from o in Order,
        where: o.status == "canceled",
        join: v in assoc(o, :variant),
        join: p in assoc(v, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [:order_payments, variant: {v, product: p}, prep_location: l, customer: c],
        order_by: [desc: o.delivery_date, desc: o.id],
        limit: ^limit,
        offset: ^offset

    canceled_orders
    |> Repo.all()
  end

  def list_delivered_and_paid_orders(limit \\ 10, offset \\ 0) do
    import Ecto.Query

    # Load a larger batch to account for orders that might not be fully paid
    # We'll load 3x the limit to ensure we get enough paid orders
    batch_size = limit * 3

    # Get delivered orders starting from the offset
    delivered_orders =
      from o in Order,
        where: o.status == "delivered",
        join: v in assoc(o, :variant),
        join: p in assoc(v, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [:order_payments, variant: {v, product: p}, prep_location: l, customer: c],
        order_by: [desc: o.delivery_date, desc: o.id],
        limit: ^batch_size,
        offset: ^offset

    # Load all orders and filter for fully paid ones, then take only the limit we need
    # order_payments already preloaded — no extra DB calls
    delivered_orders
    |> Repo.all()
    |> Enum.filter(fn order ->
      summary = payment_summary_from_preloaded(order)
      summary.fully_paid?
    end)
    |> Enum.take(limit)
  end

  def count_delivered_and_paid_orders do
    import Ecto.Query

    # Get all delivered orders with payments preloaded (single batch query)
    delivered_orders =
      from o in Order,
        where: o.status == "delivered",
        preload: [variant: :product, order_payments: []]

    # Count how many are fully paid — no N+1 since payments are preloaded
    delivered_orders
    |> Repo.all()
    |> Enum.count(fn order ->
      summary = payment_summary_from_preloaded(order)
      summary.fully_paid?
    end)
  end

  @statuses ~w(new_order in_prep ready delivered canceled)
  @delivery_types ~w(pickup delivery)

  defp maybe_filter_status(query, status) when status in @statuses do
    from o in query, where: o.status == ^status
  end

  defp maybe_filter_status(query, _), do: query

  defp maybe_filter_delivery_type(query, type) when type in @delivery_types do
    from o in query, where: o.delivery_type == ^type
  end

  defp maybe_filter_delivery_type(query, _), do: query

  defp maybe_filter_date_range(query, nil, nil), do: query
  defp maybe_filter_date_range(query, date_from, date_to) do
    {:ok, date_from} =
      if is_binary(date_from) and date_from != "" do
        Date.from_iso8601(date_from)
      else
        {:ok, nil}
      end

    {:ok, date_to} =
      if is_binary(date_to) and date_to != "" do
        Date.from_iso8601(date_to)
      else
        {:ok, nil}
      end

    query
    |> maybe_from(date_from)
    |> maybe_to(date_to)
  end

  defp maybe_filter_product_id(query, nil), do: query
  defp maybe_filter_product_id(query, ""), do: query

  defp maybe_filter_product_id(query, product_id) when is_binary(product_id) do
    case Integer.parse(product_id) do
      {id, _} ->
        from [variant: v] in query, where: v.product_id == ^id

      :error ->
        query
    end
  end

  defp maybe_from(query, nil), do: query
  defp maybe_from(query, date_from) do
    from o in query, where: o.delivery_date >= ^date_from
  end

  defp maybe_to(query, nil), do: query
  defp maybe_to(query, date_to) do
    from o in query, where: o.delivery_date <= ^date_to
  end

  defp maybe_filter_prep_location(query, nil), do: query
  defp maybe_filter_prep_location(query, ""), do: query

  defp maybe_filter_prep_location(query, prep_location_id) when is_binary(prep_location_id) do
    case Integer.parse(prep_location_id) do
      {id, _} ->
        from o in query, where: o.prep_location_id == ^id

      :error ->
        query
    end
  end

  defp maybe_filter_prep_location(query, prep_location_id) when is_integer(prep_location_id) do
    from o in query, where: o.prep_location_id == ^prep_location_id
  end

  defp apply_sort(query, sort_by, sort_dir) do
    import Ecto.Query

    dir =
      case sort_dir do
        "asc" -> :asc
        _ -> :desc
      end

    case sort_by do
      "customer_name" ->
        from [order: o] in query, order_by: [{^dir, o.customer_name}]

      "delivery_date" ->
        from [order: o] in query, order_by: [{^dir, o.delivery_date}]

      "status" ->
        from [order: o] in query, order_by: [{^dir, o.status}]

      "product" ->
        from [product: p] in query, order_by: [{^dir, p.name}]

      _ ->
        from [order: o] in query, order_by: [{^dir, o.delivery_date}]
    end
  end

  @doc """
  Gets orders for a specific month, grouped by delivery date.
  Returns a map where keys are dates (Date) and values are lists of orders.
  Excludes canceled orders by default.
  """
  def list_orders_for_calendar_month(year, month, opts \\ []) do
    import Ecto.Query

    exclude_canceled = Keyword.get(opts, :exclude_canceled, true)

    # Calculate first and last day of the month
    first_day = Date.new!(year, month, 1)
    last_day = Date.end_of_month(first_day)

    base_query =
      from o in Order,
        where: o.delivery_date >= ^first_day and o.delivery_date <= ^last_day,
        join: v in assoc(o, :variant),
        join: p in assoc(v, :product),
        join: l in assoc(o, :prep_location),
        left_join: c in assoc(o, :customer),
        preload: [variant: {v, product: p}, prep_location: l, customer: c],
        order_by: [asc: o.delivery_date, asc: o.id]

    query =
      if exclude_canceled do
        from o in base_query, where: o.status != "canceled"
      else
        base_query
      end

    orders = Repo.all(query)

    # Group orders by delivery date
    Enum.group_by(orders, & &1.delivery_date, & &1)
  end

  def get_order!(id), do: Repo.get!(Order, id) |> Repo.preload([variant: :product, prep_location: [], customer: [], order_ingredients: []])

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  def create_order(attrs) do
    Repo.transaction(fn ->
      customer_id = attrs["customer_id"] || attrs[:customer_id]
      customer_id = if customer_id in [nil, ""], do: nil, else: customer_id

      attrs =
        cond do
          customer_id ->
            customer = Customers.get_customer!(customer_id)
            maybe_update_customer_address(customer, attrs)
            populate_customer_fields(attrs, customer)

          true ->
            case handle_customer_creation(attrs) do
              {:ok, customer} ->
                attrs
                |> Map.put("customer_id", customer.id)
                |> populate_customer_fields(customer)

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
        end

      # Snapshot the current shipping fee at order creation time for historical accuracy
      attrs = Map.put_new(attrs, "shipping_fee_cents", OrderAccounting.shipping_fee_cents())

      case %Order{}
           |> Order.changeset(attrs)
           |> Repo.insert() do
        {:ok, order} ->
          # Try to create the accounting entry; if it fails, we don't crash the order creation.
          _ = OrderAccounting.record_order_created(order)
          order

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Populates denormalized customer fields on order attrs from the customer record.
  # This ensures the order always reflects the canonical customer data.
  defp populate_customer_fields(attrs, customer) do
    attrs
    |> Map.put("customer_name", customer.name)
    |> Map.put("customer_phone", customer.phone)
    |> Map.put("customer_email", customer.email || nil)
    |> populate_delivery_address_if_missing(customer)
  end

  # If the order attrs contain a non-blank delivery_address, write it back to the customer
  # so the customer record always reflects their latest known address.
  defp maybe_update_customer_address(customer, attrs) do
    address = attrs["delivery_address"] || attrs[:delivery_address]

    if address && String.trim(address) != "" do
      Customers.update_customer(customer, %{delivery_address: address})
    end

    :ok
  end

  # Helper to populate delivery_address from customer if not already provided in order
  defp populate_delivery_address_if_missing(attrs, customer) do
    delivery_address = attrs["delivery_address"] || attrs[:delivery_address]

    if (!delivery_address || String.trim(delivery_address || "") == "") &&
         customer.delivery_address &&
         String.trim(customer.delivery_address) != "" do
      Map.put(attrs, "delivery_address", customer.delivery_address)
    else
      attrs
    end
  end

  # Helper function to create a new customer when customer_id is not provided.
  # If the phone number already belongs to an existing customer, returns an error
  # prompting the user to select them from the existing customer list.
  defp handle_customer_creation(attrs) do
    customer_name = attrs["customer_name"] || attrs[:customer_name]
    customer_phone = attrs["customer_phone"] || attrs[:customer_phone]
    customer_email = attrs["customer_email"] || attrs[:customer_email]
    delivery_address = attrs["delivery_address"] || attrs[:delivery_address]

    if customer_name && customer_phone do
      # Check if a customer with this phone already exists
      case Customers.get_customer_by_phone(customer_phone) do
        %Customers.Customer{} = existing ->
          # Block creation — tell user to pick from existing list
          changeset =
            %Order{}
            |> Order.changeset(attrs)
            |> Ecto.Changeset.add_error(
              :customer_phone,
              "already belongs to #{existing.name}. Please select them from the existing customer list."
            )

          {:error, changeset}

        nil ->
          customer_attrs = %{
            name: customer_name,
            phone: customer_phone,
            email: customer_email,
            delivery_address: delivery_address
          }

          Customers.create_customer(customer_attrs)
      end
    else
      {:error, :missing_customer_info}
    end
  end

  def update_order(%Order{} = order, attrs) do
    customer_id = attrs["customer_id"] || attrs[:customer_id]
    customer_id = if customer_id in [nil, ""], do: nil, else: customer_id

    customer_name = attrs["customer_name"] || attrs[:customer_name]
    customer_phone = attrs["customer_phone"] || attrs[:customer_phone]

    cond do
      customer_id ->
        customer = Customers.get_customer!(customer_id)
        maybe_update_customer_address(customer, attrs)
        attrs = populate_customer_fields(attrs, customer)
        order |> Order.changeset(attrs) |> Repo.update()

      customer_name && customer_phone ->
        # New customer from edit form — check for duplicate phone, create if new
        case handle_customer_creation(attrs) do
          {:ok, customer} ->
            attrs =
              attrs
              |> Map.put("customer_id", customer.id)
              |> populate_customer_fields(customer)

            order |> Order.changeset(attrs) |> Repo.update()

          {:error, changeset} ->
            {:error, changeset}
        end

      true ->
        # No customer change — just update other fields
        order |> Order.changeset(attrs) |> Repo.update()
    end
  end


  def update_order_status(%Order{} = order, new_status) when new_status in @statuses do
    # Auto-set actual_delivery_date when marking as delivered
    attrs =
      if new_status == "delivered" do
        %{status: new_status, actual_delivery_date: order.actual_delivery_date || LedgrWeb.Helpers.DomainHelpers.today_mx()}
      else
        %{status: new_status}
      end

    result =
      Repo.transaction(fn ->
        {:ok, updated} =
          order
          |> Order.changeset(attrs)
          |> Repo.update()

        OrderAccounting.handle_order_status_change(updated, new_status)

        updated
      end)

    # Issue Stripe refund after the transaction commits (never inside a DB transaction)
    with {:ok, updated} <- result, true <- new_status == "canceled" do
      OrderAccounting.maybe_issue_stripe_refund(updated)
    end

    result
  end

  def update_order_status(%Order{} = _order, _bad_status) do
    {:error, :invalid_status}
  end


    # ---------------------------
  # PAYMENTS
  # ---------------------------

  def list_payments_for_order(order_id) do
    Repo.all(
      from p in OrderPayment,
        where: p.order_id == ^order_id,
        order_by: [asc: p.payment_date, asc: p.id],
        preload: [:paid_to_account]
    )
  end

  def list_all_payments do
    Repo.all(
      from p in OrderPayment,
        order_by: [desc: p.payment_date, desc: p.id],
        preload: [:order, :paid_to_account, :partner]
    )
  end

  def get_order_payment!(id) do
    Repo.get!(OrderPayment, id)
    |> Repo.preload([:order, :paid_to_account, :partner, :partner_payable_account])
  end

  def change_order_payment(%OrderPayment{} = payment, attrs \\ %{}) do
    OrderPayment.changeset(payment, attrs)
  end

  def create_order_payment(attrs) do
    Repo.transaction(fn ->
      with {:ok, payment} <-
             %OrderPayment{}
             |> OrderPayment.changeset(attrs)
             |> Repo.insert(),
           {:ok, _entry} <- OrderAccounting.record_order_payment(payment) do
        payment
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def update_order_payment(%OrderPayment{} = payment, attrs) do
    Repo.transaction(fn ->
      with {:ok, payment} <-
             payment
             |> OrderPayment.changeset(attrs)
             |> Repo.update(),
           payment <- payment |> Repo.preload([:order, :paid_to_account, :partner, :partner_payable_account]),
           {:ok, _entry} <- OrderAccounting.update_order_payment_journal_entry(payment) do
        payment
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def delete_order_payment(%OrderPayment{} = payment) do
    Repo.transaction(fn ->
      # Find and delete the related journal entry
      reference = "Order ##{payment.order_id} payment ##{payment.id}"

      journal_entry =
        from(je in Ledgr.Core.Accounting.JournalEntry, where: je.reference == ^reference)
        |> Repo.one()

      if journal_entry do
        Repo.delete!(journal_entry)
      end

      # Delete the payment
      Repo.delete!(payment)
    end)
    |> case do
      {:ok, payment} -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

    # ---------------------------
  # PAYMENT SUMMARY PER ORDER
  # ---------------------------

  def payment_summary(%Order{} = order) do
    order = Repo.preload(order, [variant: :product, order_payments: []])
    compute_payment_summary(order, order.order_payments)
  end

  @doc """
  Compute payment summary from an order that already has :variant and :order_payments preloaded.
  No additional DB queries — use this in batch/list contexts to avoid N+1.
  """
  def payment_summary_from_preloaded(%Order{} = order) do
    payments = order.order_payments || []
    compute_payment_summary(order, payments)
  end

  defp compute_payment_summary(%Order{} = order, payments) when is_list(payments) do
    total_paid_cents =
      Enum.reduce(payments, 0, fn p, acc ->
        (p.amount_cents || 0) + acc
      end)

    unit_price_cents = resolve_unit_price(order)

    quantity = order.quantity || 1
    original_price_cents = unit_price_cents * quantity

    discount_cents = calculate_discount_cents(order, original_price_cents)

    {product_total_cents, shipping_cents} = order_total_cents(order)
    order_total_cents = product_total_cents + shipping_cents

    outstanding_cents = max(order_total_cents - total_paid_cents, 0)
    overpaid_cents = max(total_paid_cents - order_total_cents, 0)

    product_paid_cents = min(total_paid_cents, product_total_cents)
    shipping_paid_cents = min(max(0, total_paid_cents - product_total_cents), shipping_cents)

    if order.is_gift do
      %{
        product_total_cents: product_total_cents,
        original_price_cents: original_price_cents,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        order_total_cents: 0,
        total_paid_cents: 0,
        product_paid_cents: 0,
        shipping_paid_cents: 0,
        outstanding_cents: 0,
        overpaid_cents: 0,
        fully_paid?: true,
        partially_paid?: false
      }
    else
      %{
        product_total_cents: product_total_cents,
        original_price_cents: original_price_cents,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        order_total_cents: order_total_cents,
        total_paid_cents: total_paid_cents,
        product_paid_cents: product_paid_cents,
        shipping_paid_cents: shipping_paid_cents,
        outstanding_cents: outstanding_cents,
        overpaid_cents: overpaid_cents,
        fully_paid?: outstanding_cents == 0 and order_total_cents > 0,
        partially_paid?: total_paid_cents > 0 and outstanding_cents > 0
      }
    end
  end

  def order_total_cents(%Order{} = order) do
    order = Repo.preload(order, [:variant])

    unit_price = resolve_unit_price(order)

    quantity = order.quantity || 1
    base = unit_price * quantity

    # Apply discount to the total base price (unit price * quantity)
    discount_cents = calculate_discount_cents(order, base)
    discounted_base = max(base - discount_cents, 0)

    shipping_cents =
      if order.customer_paid_shipping do
        # Use stored shipping fee if available, fallback to current catalog price for legacy orders
        order.shipping_fee_cents || OrderAccounting.shipping_fee_cents()
      else
        0
      end

    {discounted_base, shipping_cents}
  end

  defp calculate_discount_cents(%Order{discount_type: "flat", discount_value: value}, _base)
       when not is_nil(value) do
    # discount_value is in pesos, convert to cents
    value
    |> Decimal.mult(Decimal.new(100))
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp calculate_discount_cents(%Order{discount_type: "percentage", discount_value: value}, base)
       when not is_nil(value) do
    # Calculate percentage of base price
    base
    |> Decimal.new()
    |> Decimal.mult(value)
    |> Decimal.div(Decimal.new(100))
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp calculate_discount_cents(_order, _base), do: 0

  # ORDER INGREDIENTS

  def update_order_ingredients(%Order{} = order, ingredients_attrs) when is_list(ingredients_attrs) do
    Repo.transaction(fn ->
      # Delete existing order ingredients
      Repo.delete_all(from oi in OrderIngredient, where: oi.order_id == ^order.id)

      # Insert new order ingredients
      Enum.each(ingredients_attrs, fn attrs ->
        %OrderIngredient{}
        |> OrderIngredient.changeset(Map.put(attrs, "order_id", order.id))
        |> Repo.insert!()
      end)

      # Reload order with ingredients
      Repo.get!(Order, order.id) |> Repo.preload([variant: :product, prep_location: [], customer: [], order_ingredients: []])
    end)
  end

  def update_order_ingredients(%Order{} = _order, _), do: {:error, :invalid_attrs}

  # ---------------------------------------------------------------------------
  # Stripe integration
  # ---------------------------------------------------------------------------

  @doc """
  Returns all orders associated with a Stripe Checkout Session ID.
  Used by the success page and webhook idempotency checks.
  """
  def get_orders_by_stripe_session(stripe_session_id) do
    from(o in Order,
      where: o.stripe_checkout_session_id == ^stripe_session_id,
      join: v in assoc(o, :variant),
      join: p in assoc(v, :product),
      preload: [variant: {v, product: p}]
    )
    |> Repo.all()
  end

  @doc """
  Saves the Stripe Checkout Session ID on an order so the success page can find it.
  Called when the admin generates a payment link for an existing order.
  """
  def set_stripe_checkout_session(order_id, stripe_session_id) do
    Repo.get!(Order, order_id)
    |> Order.changeset(%{"stripe_checkout_session_id" => stripe_session_id})
    |> Repo.update()
  end

  @doc """
  Creates one order per cart item from a completed Stripe checkout, then records
  a payment on each order. Called from the Stripe webhook after
  `checkout.session.completed`.

  Each order gets:
    - `stripe_checkout_session_id` — for lookup on the success page
    - An `OrderPayment` with `method: "stripe"` and `paid_to_account_id` pointing
      to account 1005 (Stripe Receivable), which auto-creates the journal entry.
  """
  def create_orders_from_pending_checkout(%PendingCheckout{} = pending, stripe_session_id) do
    stripe_account = Accounting.get_account_by_code!("1005")
    default_location = Repo.get_by!(Location, code: "CASA_AG")
    customer = Customers.get_customer!(pending.customer_id)
    checkout_attrs = pending.checkout_attrs

    delivery_date =
      case Date.from_iso8601(checkout_attrs["delivery_date"] || "") do
        {:ok, d} -> d
        _ -> LedgrWeb.Helpers.DomainHelpers.today_mx()
      end

    delivery_type = checkout_attrs["delivery_type"] || "pickup"

    customer_paid_shipping = delivery_type == "delivery"

    Repo.transaction(fn ->
      Enum.map(pending.cart, fn {variant_id_str, quantity} ->
        quantity = if is_integer(quantity), do: quantity, else: String.to_integer("#{quantity}")
        {variant_id, _} = Integer.parse("#{variant_id_str}")

        order_attrs = %{
          "customer_id" => customer.id,
          "variant_id" => variant_id,
          "quantity" => quantity,
          "delivery_type" => delivery_type,
          "delivery_date" => delivery_date,
          "delivery_address" => checkout_attrs["delivery_address"],
          "special_instructions" => checkout_attrs["special_instructions"],
          "prep_location_id" => default_location.id,
          "customer_paid_shipping" => customer_paid_shipping,
          "stripe_checkout_session_id" => stripe_session_id,
          "discount_type" => checkout_attrs["discount_type"],
          "discount_value" => checkout_attrs["discount_value"]
        }

        order =
          case create_order(order_attrs) do
            {:ok, o} -> o
            {:error, reason} -> Repo.rollback(reason)
          end

        order = Repo.preload(order, [:variant, :order_payments])
        summary = payment_summary_from_preloaded(order)
        amount_cents = summary.order_total_cents

        payment_attrs = %{
          "order_id" => order.id,
          "amount_cents" => amount_cents,
          "paid_to_account_id" => stripe_account.id,
          "method" => "stripe",
          "payment_date" => LedgrWeb.Helpers.DomainHelpers.today_mx(),
          "is_deposit" => false
        }

        case create_order_payment(payment_attrs) do
          {:ok, _payment} -> order
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  @doc """
  Records Stripe payments for existing COD orders that the customer chose to pay online.
  Updates each order's `stripe_checkout_session_id` and creates an `OrderPayment` with
  method "stripe". Idempotent — skips orders that already have a Stripe payment.
  """
  def create_payments_for_existing_orders(order_ids, stripe_session_id) do
    stripe_account = Accounting.get_account_by_code!("1005")

    Repo.transaction(fn ->
      Enum.each(order_ids, fn order_id ->
        order = Repo.get!(Order, order_id) |> Repo.preload([:variant, :order_payments])

        # Idempotency: skip if already has a Stripe payment
        already_paid = Enum.any?(order.order_payments, fn p -> p.method == "stripe" end)

        unless already_paid do
          order
          |> Order.changeset(%{"stripe_checkout_session_id" => stripe_session_id})
          |> Repo.update!()

          summary = payment_summary_from_preloaded(order)
          amount_cents = summary.product_total_cents

          payment_attrs = %{
            "order_id" => order_id,
            "amount_cents" => amount_cents,
            "paid_to_account_id" => stripe_account.id,
            "method" => "stripe",
            "payment_date" => LedgrWeb.Helpers.DomainHelpers.today_mx(),
            "is_deposit" => false
          }

          case create_order_payment(payment_attrs) do
            {:ok, _payment} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end
      end)
    end)
  end

  @doc """
  Records a Stripe payment for the shipping fee on an existing order.
  Called from the webhook when a shipping-only Stripe session completes.
  """
  def create_shipping_payment(order_id, amount_cents) do
    stripe_account = Accounting.get_account_by_code!("1005")
    order = Repo.get!(Order, order_id)

    payment_attrs = %{
      "order_id" => order_id,
      "amount_cents" => amount_cents,
      "paid_to_account_id" => stripe_account.id,
      "method" => "stripe",
      "payment_date" => LedgrWeb.Helpers.DomainHelpers.today_mx(),
      "is_deposit" => order.status != "delivered"
    }

    create_order_payment(payment_attrs)
  end

  def create_orders_cod(cart, customer_id, checkout_attrs) do
    default_location = Repo.get_by!(Location, code: "CASA_AG")
    customer = Customers.get_customer!(customer_id)

    delivery_date =
      case Date.from_iso8601(checkout_attrs["delivery_date"] || "") do
        {:ok, d} -> d
        _ -> LedgrWeb.Helpers.DomainHelpers.today_mx()
      end

    delivery_type = checkout_attrs["delivery_type"] || "pickup"
    customer_paid_shipping = delivery_type == "delivery"

    Repo.transaction(fn ->
      Enum.map(cart, fn {variant_id_str, quantity} ->
        quantity = if is_integer(quantity), do: quantity, else: String.to_integer("#{quantity}")
        {variant_id, _} = Integer.parse("#{variant_id_str}")

        order_attrs = %{
          "customer_id" => customer.id,
          "variant_id" => variant_id,
          "quantity" => quantity,
          "delivery_type" => delivery_type,
          "delivery_date" => delivery_date,
          "delivery_address" => checkout_attrs["delivery_address"],
          "special_instructions" => checkout_attrs["special_instructions"],
          "prep_location_id" => default_location.id,
          "customer_paid_shipping" => customer_paid_shipping,
          "discount_type" => checkout_attrs["discount_type"],
          "discount_value" => checkout_attrs["discount_value"]
        }

        case create_order(order_attrs) do
          {:ok, order} -> order
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Discount codes
  # ---------------------------------------------------------------------------

  def list_discount_codes do
    Repo.all(from d in DiscountCode, order_by: [desc: d.inserted_at])
  end

  def get_discount_code!(id), do: Repo.get!(DiscountCode, id)

  def create_discount_code(attrs) do
    %DiscountCode{}
    |> DiscountCode.changeset(attrs)
    |> Repo.insert()
  end

  def update_discount_code(%DiscountCode{} = code, attrs) do
    code
    |> DiscountCode.changeset(attrs)
    |> Repo.update()
  end

  def delete_discount_code(%DiscountCode{} = code), do: Repo.delete(code)

  @doc """
  Validates a discount code string for use at checkout.
  Returns `{:ok, discount_code}` or `{:error, reason_string}`.
  """
  def validate_discount_code(code_str) when is_binary(code_str) do
    code_str = String.upcase(String.trim(code_str))

    case Repo.get_by(DiscountCode, code: code_str) do
      nil ->
        {:error, "Código de descuento inválido"}

      %DiscountCode{active: false} ->
        {:error, "Este código no está activo"}

      %DiscountCode{expires_at: exp} = code when not is_nil(exp) ->
        if Date.compare(LedgrWeb.Helpers.DomainHelpers.today_mx(), exp) == :gt do
          {:error, "Este código ha expirado"}
        else
          check_uses(code)
        end

      code ->
        check_uses(code)
    end
  end

  def validate_discount_code(_), do: {:error, "Código de descuento inválido"}

  defp check_uses(%DiscountCode{max_uses: max, uses_count: used} = code) when not is_nil(max) do
    if used >= max, do: {:error, "Este código ya no tiene usos disponibles"}, else: {:ok, code}
  end

  defp check_uses(code), do: {:ok, code}

  def increment_discount_code_uses(%DiscountCode{} = code) do
    Repo.update_all(
      from(d in DiscountCode, where: d.id == ^code.id),
      inc: [uses_count: 1]
    )
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_unit_price(%Order{variant: %ProductVariant{price_cents: p}}) when is_integer(p), do: p
  defp resolve_unit_price(_), do: 0

end
