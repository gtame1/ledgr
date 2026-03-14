defmodule LedgrWeb.Router do
  use LedgrWeb, :router

  import LedgrWeb.Router.CoreRoutes

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LedgrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LedgrWeb.Plugs.DomainPlug
    plug LedgrWeb.Plugs.LedgrAccessPlug
  end

  pipeline :require_auth do
    plug LedgrWeb.Plugs.AuthPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── Landing page (no domain context) ────────────────────────────────
  scope "/", LedgrWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/apps", PageController, :apps
    get "/unlock", UnlockController, :new
    post "/unlock", UnlockController, :create
  end

  # ── MrMunchMe: public storefront ────────────────────────────────────
  scope "/mr-munch-me", LedgrWeb.Storefront do
    pipe_through :browser

    get "/menu", MenuController, :index
    get "/menu/:id", MenuController, :show

    # Cart
    get "/cart", CartController, :index
    post "/cart/add", CartController, :add
    put "/cart/update", CartController, :update
    post "/cart/remove", CartController, :remove

    # Checkout
    get "/checkout", CheckoutController, :new
    post "/checkout", CheckoutController, :create
    get "/checkout/success", CheckoutController, :success
    get "/checkout/cancel", CheckoutController, :cancel
    post "/checkout/pay-existing", CheckoutController, :pay_existing_with_stripe
  end

  # ── Stripe webhooks (no CSRF, no browser session) ───────────────────
  scope "/webhooks", LedgrWeb.Storefront do
    pipe_through :api

    post "/stripe", StripeWebhookController, :handle
  end

  # ── MrMunchMe: public auth routes ──────────────────────────────────
  scope "/app/mr-munch-me", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── MrMunchMe: protected routes ────────────────────────────────────
  scope "/app/mr-munch-me", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes()

    # MrMunchMe-specific routes
    get "/orders/calendar", Domains.MrMunchMe.OrderController, :calendar
    get "/orders/:id/stripe-link", Domains.MrMunchMe.OrderController, :stripe_link
    resources "/orders", Domains.MrMunchMe.OrderController, only: [:index, :show, :new, :create, :edit, :update]
    post "/orders/:id/status", Domains.MrMunchMe.OrderController, :update_status
    post "/orders/:id/ingredients", Domains.MrMunchMe.OrderController, :update_ingredients
    get "/orders/:id/payments/new", Domains.MrMunchMe.OrderController, :new_payment
    post "/orders/:id/payments", Domains.MrMunchMe.OrderController, :create_payment

    resources "/order_payments", Domains.MrMunchMe.OrderPaymentController, only: [:index, :show, :edit, :update, :delete]

    get "/inventory", Domains.MrMunchMe.InventoryController, :index
    get  "/inventory/purchases/new", Domains.MrMunchMe.InventoryController, :new_purchase
    post "/inventory/purchases",     Domains.MrMunchMe.InventoryController, :create_purchase
    get  "/inventory/purchases/:id/edit", Domains.MrMunchMe.InventoryController, :edit_purchase
    put  "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :update_purchase
    delete "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :delete_purchase
    post "/inventory/purchases/:id/return", Domains.MrMunchMe.InventoryController, :return_purchase
    get  "/inventory/movements/new", Domains.MrMunchMe.InventoryController, :new_movement
    post "/inventory/movements",     Domains.MrMunchMe.InventoryController, :create_movement
    get  "/inventory/movements/:id/edit", Domains.MrMunchMe.InventoryController, :edit_movement
    put  "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :update_movement
    delete "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :delete_movement
    get "/inventory/requirements", Domains.MrMunchMe.InventoryController, :requirements

    resources "/products", Domains.MrMunchMe.ProductController, only: [:index, :new, :create, :edit, :update, :delete]
    patch "/products/:id/toggle_active", Domains.MrMunchMe.ProductController, :toggle_active
    patch "/products/:id/move_up", Domains.MrMunchMe.ProductController, :move_up
    patch "/products/:id/move_down", Domains.MrMunchMe.ProductController, :move_down
    post "/products/:product_id/images", Domains.MrMunchMe.ProductController, :upload_gallery_image
    delete "/products/:product_id/images/:image_id", Domains.MrMunchMe.ProductController, :delete_gallery_image
    resources "/products/:product_id/variants", Domains.MrMunchMe.VariantController, only: [:new, :create, :edit, :update, :delete]
    post "/products/:product_id/variants/:variant_id/recipe", Domains.MrMunchMe.VariantController, :save_recipe
    resources "/ingredients", Domains.MrMunchMe.IngredientController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/recipes", Domains.MrMunchMe.RecipeController, only: [:index, :new, :create, :show, :edit, :delete]
    post "/recipes/new_version/:id", Domains.MrMunchMe.RecipeController, :create_new_version
  end

  # ── Viaxe: public auth routes ──────────────────────────────────────
  scope "/app/viaxe", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Viaxe: protected routes ────────────────────────────────────────
  scope "/app/viaxe", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes_no_customers()

    # Viaxe customer routes (richer travel-specific schema)
    resources "/customers", Domains.Viaxe.CustomerController do
      post "/passports", Domains.Viaxe.PassportController, :create
      delete "/passports/:passport_id", Domains.Viaxe.PassportController, :delete
      post "/visas", Domains.Viaxe.VisaController, :create
      delete "/visas/:visa_id", Domains.Viaxe.VisaController, :delete
      post "/loyalty_programs", Domains.Viaxe.LoyaltyProgramController, :create
      delete "/loyalty_programs/:loyalty_program_id", Domains.Viaxe.LoyaltyProgramController, :delete
    end

    # Trips (umbrella container for related bookings)
    resources "/trips", Domains.Viaxe.TripController
    get "/trips/:id/calendar", Domains.Viaxe.TripController, :calendar

    # Bookings (with type-specific details)
    resources "/bookings", Domains.Viaxe.BookingController, only: [:index, :show, :new, :create, :edit, :update, :delete]
    post "/bookings/:id/status", Domains.Viaxe.BookingController, :update_status

    # Services catalog
    resources "/services", Domains.Viaxe.ServiceController, only: [:index, :new, :create, :edit, :update, :delete]

    # Suppliers (with location info)
    resources "/suppliers", Domains.Viaxe.SupplierController

    # Recommendations (curated reference by city)
    resources "/recommendations", Domains.Viaxe.RecommendationController

    # Travel documents overview (all passports, visas, loyalty programs)
    get "/documents", Domains.Viaxe.DocumentController, :index
  end

  # ── Volume Studio: public auth routes ─────────────────────────────
  scope "/app/volume-studio", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Volume Studio: protected routes ───────────────────────────────
  scope "/app/volume-studio", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes_no_customers()

    # Customers (studio members)
    resources "/customers", CustomerController

    # Class sessions with check-in
    resources "/class-sessions", Domains.VolumeStudio.ClassSessionController, only: [:index, :show, :new, :create, :edit, :update, :delete]
    post "/class-sessions/:id/checkin/:booking_id", Domains.VolumeStudio.ClassSessionController, :checkin
    get  "/class-sessions/:id/bookings/new",        Domains.VolumeStudio.ClassSessionController, :new_booking
    post "/class-sessions/:id/bookings",            Domains.VolumeStudio.ClassSessionController, :create_booking
    post "/class-sessions/:id/bookings/:booking_id/cancel", Domains.VolumeStudio.ClassSessionController, :cancel_booking

    # Instructors
    resources "/instructors", Domains.VolumeStudio.InstructorController, only: [:index, :new, :create, :edit, :update, :delete]

    # Subscription plans & member subscriptions
    resources "/subscription-plans", Domains.VolumeStudio.SubscriptionPlanController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/subscriptions", Domains.VolumeStudio.SubscriptionController, only: [:index, :show, :new, :create, :edit, :update]
    get  "/subscriptions/:id/bookings/new", Domains.VolumeStudio.SubscriptionController, :new_booking
    post "/subscriptions/:id/bookings",     Domains.VolumeStudio.SubscriptionController, :create_booking
    get  "/subscriptions/:id/payment/new", Domains.VolumeStudio.SubscriptionController, :new_payment
    post "/subscriptions/:id/payment", Domains.VolumeStudio.SubscriptionController, :record_payment
    get  "/subscriptions/:id/payment/:entry_id/edit", Domains.VolumeStudio.SubscriptionController, :edit_payment
    put  "/subscriptions/:id/payment/:entry_id", Domains.VolumeStudio.SubscriptionController, :update_payment
    delete "/subscriptions/:id/payment/:entry_id", Domains.VolumeStudio.SubscriptionController, :delete_payment
    get  "/subscriptions/:id/cancel", Domains.VolumeStudio.SubscriptionController, :new_cancel
    post "/subscriptions/:id/cancel", Domains.VolumeStudio.SubscriptionController, :cancel

    # Diet consultations
    resources "/consultations", Domains.VolumeStudio.ConsultationController, only: [:index, :show, :new, :create, :edit, :update]
    post "/consultations/:id/payment", Domains.VolumeStudio.ConsultationController, :record_payment

    # Studio spaces & rental agreements
    resources "/spaces", Domains.VolumeStudio.SpaceController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/space-rentals", Domains.VolumeStudio.SpaceRentalController, only: [:index, :show, :new, :create, :edit, :update]
    post "/space-rentals/:id/payment", Domains.VolumeStudio.SpaceRentalController, :record_payment
  end

  # ── API endpoints (core) ─────────────────────────────────────────────
  scope "/api", LedgrWeb do
    pipe_through :api

    # Customers
    get "/customers", ApiController, :list_customers
    get "/customers/check_phone/:phone", ApiController, :check_customer_phone
    get "/customers/:id", ApiController, :show_customer

    # Accounting
    get "/accounts", ApiController, :list_accounts
    get "/accounts/:id", ApiController, :show_account
    get "/journal_entries", ApiController, :list_journal_entries
    get "/journal_entries/:id", ApiController, :show_journal_entry

    # Reports
    get "/reports/balance_sheet", ApiController, :balance_sheet
    get "/reports/profit_and_loss", ApiController, :profit_and_loss
  end

  # ── API endpoints (MrMunchMe domain) ───────────────────────────────
  scope "/api/mr-munch-me", LedgrWeb do
    pipe_through :api

    # Products
    get "/products", Domains.MrMunchMe.ApiController, :list_products
    get "/products/:id", Domains.MrMunchMe.ApiController, :show_product

    # Orders
    get "/orders", Domains.MrMunchMe.ApiController, :list_orders
    get "/orders/:id", Domains.MrMunchMe.ApiController, :show_order

    # Inventory
    get "/ingredients", Domains.MrMunchMe.ApiController, :list_ingredients
    get "/ingredients/:id", Domains.MrMunchMe.ApiController, :show_ingredient
    get "/stock", Domains.MrMunchMe.ApiController, :list_stock
    get "/locations", Domains.MrMunchMe.ApiController, :list_locations
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ledgr, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LedgrWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
