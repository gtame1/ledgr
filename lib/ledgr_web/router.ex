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
    get "/checkout/validate-discount", CheckoutController, :validate_discount
  end

  # ── Stripe webhooks (no CSRF, no browser session) ───────────────────
  scope "/webhooks", LedgrWeb.Storefront do
    pipe_through :api

    post "/stripe", StripeWebhookController, :handle
  end

  scope "/webhooks", LedgrWeb do
    pipe_through :api

    post "/hello-doctor-stripe", HelloDoctorStripeWebhookController, :handle
    post "/aumenta-mi-pension-stripe", AumentaMiPensionStripeWebhookController, :handle
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
    get "/more", ReportController, :mr_munch_me_more
    get "/orders/calendar", Domains.MrMunchMe.OrderController, :calendar
    get "/orders/:id/stripe-link", Domains.MrMunchMe.OrderController, :stripe_link
    get "/orders/:id/shipping-link", Domains.MrMunchMe.OrderController, :shipping_link
    post "/orders/:id/shipping-link", Domains.MrMunchMe.OrderController, :create_shipping_link
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
    resources "/discount-codes", Domains.MrMunchMe.DiscountCodeController, only: [:index, :new, :create, :edit, :update, :delete]
    patch "/discount-codes/:id/toggle-active", Domains.MrMunchMe.DiscountCodeController, :toggle_active
    resources "/ingredients", Domains.MrMunchMe.IngredientController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/recipes", Domains.MrMunchMe.RecipeController, only: [:index, :new, :create, :show, :edit, :delete]
    post "/recipes/new_version/:id", Domains.MrMunchMe.RecipeController, :create_new_version

    # Inventory reconciliation (MrMunchMe-specific)
    get "/reconciliation/inventory", ReconciliationController, :inventory_index
    post "/reconciliation/inventory/adjust", ReconciliationController, :inventory_adjust
    post "/reconciliation/inventory/reconcile_all", ReconciliationController, :inventory_reconcile_all
    post "/reconciliation/inventory/quick_transfer", ReconciliationController, :inventory_quick_transfer
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
    get "/class-sessions/calendar", Domains.VolumeStudio.ClassSessionController, :calendar
    resources "/class-sessions", Domains.VolumeStudio.ClassSessionController, only: [:index, :show, :new, :create, :edit, :update, :delete]
    post "/class-sessions/:id/checkin/:booking_id", Domains.VolumeStudio.ClassSessionController, :checkin
    get  "/class-sessions/:id/bookings/new",        Domains.VolumeStudio.ClassSessionController, :new_booking
    post "/class-sessions/:id/bookings",            Domains.VolumeStudio.ClassSessionController, :create_booking
    post "/class-sessions/:id/bookings/:booking_id/cancel",     Domains.VolumeStudio.ClassSessionController, :cancel_booking
    post "/class-sessions/:id/bookings/:booking_id/attendance", Domains.VolumeStudio.ClassSessionController, :mark_attendance
    post "/class-sessions/:id/status",                          Domains.VolumeStudio.ClassSessionController, :update_status

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
    post "/subscriptions/:id/status", Domains.VolumeStudio.SubscriptionController, :update_status
    post "/subscriptions/:id/redeem", Domains.VolumeStudio.SubscriptionController, :redeem
    get  "/subscriptions/:id/reactivate", Domains.VolumeStudio.SubscriptionController, :new_reactivate
    post "/subscriptions/:id/reactivate", Domains.VolumeStudio.SubscriptionController, :reactivate

    # Diet consultations
    resources "/consultations", Domains.VolumeStudio.ConsultationController, only: [:index, :show, :new, :create, :edit, :update]
    post "/consultations/:id/status",      Domains.VolumeStudio.ConsultationController, :update_status
    get  "/consultations/:id/payment/new", Domains.VolumeStudio.ConsultationController, :new_payment
    post "/consultations/:id/payment",     Domains.VolumeStudio.ConsultationController, :record_payment

    # Studio spaces & rental agreements
    resources "/spaces", Domains.VolumeStudio.SpaceController, only: [:index, :new, :create, :edit, :update, :delete]
    resources "/space-rentals", Domains.VolumeStudio.SpaceRentalController, only: [:index, :show, :new, :create, :edit, :update]
    get  "/space-rentals/:id/payment/new", Domains.VolumeStudio.SpaceRentalController, :new_payment
    post "/space-rentals/:id/payment",     Domains.VolumeStudio.SpaceRentalController, :record_payment

    # Quick Sale (extra / one-time items — step 1: create subscription)
    get  "/quick-sale/new", Domains.VolumeStudio.QuickSaleController, :new
    post "/quick-sale",     Domains.VolumeStudio.QuickSaleController, :create
  end

  # ── Ledgr HQ: public auth routes ───────────────────────────────────
  scope "/app/ledgr", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Ledgr HQ: protected routes ─────────────────────────────────────
  scope "/app/ledgr", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes()

    # Clients
    resources "/clients", Domains.LedgrHQ.ClientController
    post "/clients/:id/status", Domains.LedgrHQ.ClientController, :update_status

    # Subscription plans (ledgr's own plans)
    resources "/subscription-plans", Domains.LedgrHQ.SubscriptionPlanController,
      only: [:index, :new, :create, :edit, :update, :delete]

    # Client subscriptions
    resources "/client-subscriptions", Domains.LedgrHQ.ClientSubscriptionController,
      only: [:index, :show, :new, :create, :edit, :update]
    post "/client-subscriptions/:id/status", Domains.LedgrHQ.ClientSubscriptionController, :update_status

    # Costs
    resources "/costs", Domains.LedgrHQ.CostController,
      only: [:index, :new, :create, :edit, :update, :delete]
    patch "/costs/:id/toggle_active", Domains.LedgrHQ.CostController, :toggle_active
  end

  # ── Casa Tame: public auth routes ──────────────────────────────────
  scope "/app/casa-tame", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Casa Tame: protected routes ───────────────────────────────────
  scope "/app/casa-tame", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes_personal_finance()

    # Expenses (domain-specific with currency + categories)
    resources "/expenses", Domains.CasaTame.ExpenseController,
      only: [:index, :new, :create, :show, :edit, :update, :delete]

    # Income
    resources "/income", Domains.CasaTame.IncomeController,
      only: [:index, :new, :create, :show, :edit, :update, :delete]

    # Expense categories
    resources "/categories", Domains.CasaTame.CategoryController,
      only: [:index, :new, :create, :edit, :update, :delete]

    # Investment accounts (read-only list + record movements)
    get "/investment-accounts", Domains.CasaTame.InvestmentAccountController, :index
    get "/investment-accounts/:id", Domains.CasaTame.InvestmentAccountController, :show
    post "/investment-accounts/:id/movements", Domains.CasaTame.InvestmentAccountController, :create_movement

    # Debt accounts (read-only list + record movements)
    get "/debt-accounts", Domains.CasaTame.DebtAccountController, :index
    get "/debt-accounts/:id", Domains.CasaTame.DebtAccountController, :show
    post "/debt-accounts/:id/movements", Domains.CasaTame.DebtAccountController, :create_movement

    # Bills & recurring payments
    get "/bills/calendar", Domains.CasaTame.BillController, :calendar
    resources "/bills", Domains.CasaTame.BillController, only: [:index, :new, :create, :edit, :update, :delete]
    post "/bills/:id/mark-paid", Domains.CasaTame.BillController, :mark_paid

    # FX Transfers (cross-currency)
    get "/fx-transfers/new", Domains.CasaTame.FxTransferController, :new
    post "/fx-transfers", Domains.CasaTame.FxTransferController, :create

    # Domain-specific reports
    get "/reports", Domains.CasaTame.ReportController, :reports_hub
    get "/reports/net-worth", Domains.CasaTame.ReportController, :net_worth
    get "/reports/monthly-trends", Domains.CasaTame.ReportController, :monthly_trends
    get "/reports/category-breakdown", Domains.CasaTame.ReportController, :category_breakdown
  end

  # ── Hello Doctor: public auth routes ────────────────────────────────
  scope "/app/hello-doctor", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Hello Doctor: protected routes ─────────────────────────────────
  scope "/app/hello-doctor", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes_no_customers()

    # Conversations (all WhatsApp conversations, including those without consultations)
    resources "/conversations", Domains.HelloDoctor.ConversationListController, only: [:index, :show]

    # Doctor assistant chats
    resources "/doctor-chats", Domains.HelloDoctor.DoctorChatController, only: [:index, :show]

    # Consultations (read-only — bot creates consultations)
    resources "/consultations", Domains.HelloDoctor.ConsultationController, only: [:index, :show]
    post "/consultations/:id/status", Domains.HelloDoctor.ConsultationController, :update_status

    # Doctors (read-only — bot manages doctors)
    resources "/doctors", Domains.HelloDoctor.DoctorController, only: [:index, :show, :new, :create, :edit, :update]
    post "/doctors/:id/toggle-status", Domains.HelloDoctor.DoctorController, :toggle_status

    # Patients (read-only — bot manages patients)
    resources "/patients", Domains.HelloDoctor.PatientController, only: [:index, :show]

    # Payments (queries consultations with payment data)
    resources "/payments", Domains.HelloDoctor.PaymentController, only: [:index, :show]
    post "/payments/sync", Domains.HelloDoctor.PaymentController, :sync
    post "/payments/:id/refund", Domains.HelloDoctor.PaymentController, :refund
    post "/payments/:id/check-status", Domains.HelloDoctor.PaymentController, :check_status
    get "/payments/:id/link", Domains.HelloDoctor.PaymentController, :link_form
    post "/payments/:id/link", Domains.HelloDoctor.PaymentController, :save_link
    post "/payments/:id/unlink", Domains.HelloDoctor.PaymentController, :unlink

    # Specialties (admin-managed list)
    resources "/specialties", Domains.HelloDoctor.SpecialtyController, only: [:index, :create, :delete]
    patch "/specialties/:id/toggle", Domains.HelloDoctor.SpecialtyController, :toggle
  end

  # ── Aumenta Mi Pensión: public auth routes ─────────────────────────
  scope "/app/aumenta-mi-pension", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Aumenta Mi Pensión: protected routes ───────────────────────────
  scope "/app/aumenta-mi-pension", LedgrWeb do
    pipe_through [:browser, :require_auth]

    core_routes_no_customers()

    resources "/conversations", Domains.AumentaMiPension.ConversationListController, only: [:index, :show]
    resources "/agent-chats", Domains.AumentaMiPension.AgentChatController, only: [:index, :show]

    resources "/consultations", Domains.AumentaMiPension.ConsultationController, only: [:index, :show]
    post "/consultations/:id/status", Domains.AumentaMiPension.ConsultationController, :update_status

    resources "/agents", Domains.AumentaMiPension.AgentController, only: [:index, :show, :new, :create, :edit, :update]
    post "/agents/:id/toggle-status", Domains.AumentaMiPension.AgentController, :toggle_status

    resources "/customers", Domains.AumentaMiPension.CustomerController, only: [:index, :show]

    resources "/pension-cases", Domains.AumentaMiPension.PensionCaseController, only: [:index, :show]

    resources "/payments", Domains.AumentaMiPension.PaymentController, only: [:index, :show]
    post "/payments/sync", Domains.AumentaMiPension.PaymentController, :sync
    post "/payments/:id/refund", Domains.AumentaMiPension.PaymentController, :refund
    post "/payments/:id/check-status", Domains.AumentaMiPension.PaymentController, :check_status
    get "/payments/:id/link", Domains.AumentaMiPension.PaymentController, :link_form
    post "/payments/:id/link", Domains.AumentaMiPension.PaymentController, :save_link
    post "/payments/:id/unlink", Domains.AumentaMiPension.PaymentController, :unlink
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
