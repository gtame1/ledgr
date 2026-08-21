defmodule LedgrWeb.Router do
  use LedgrWeb, :router

  import LedgrWeb.Router.CoreRoutes

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug LedgrWeb.Plugs.RequestLoggerPlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {LedgrWeb.Layouts, :root}
    plug LedgrWeb.Plugs.CSRFProtectionPlug
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
  end

  # AMP webhook lives under /app/aumenta-mi-pension/stripe to match the
  # domain's path prefix. It's a *public* POST (no auth) despite the prefix
  # — Stripe can't authenticate — and is defined in its own :api-pipelined
  # scope so it stays outside the authenticated AMP area.
  scope "/app/aumenta-mi-pension", LedgrWeb do
    pipe_through :api

    post "/stripe", AumentaMiPensionStripeWebhookController, :handle
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

    resources "/orders", Domains.MrMunchMe.OrderController,
      only: [:index, :show, :new, :create, :edit, :update]

    post "/orders/:id/status", Domains.MrMunchMe.OrderController, :update_status
    post "/orders/:id/ingredients", Domains.MrMunchMe.OrderController, :update_ingredients
    get "/orders/:id/payments/new", Domains.MrMunchMe.OrderController, :new_payment
    post "/orders/:id/payments", Domains.MrMunchMe.OrderController, :create_payment

    resources "/order_payments", Domains.MrMunchMe.OrderPaymentController,
      only: [:index, :show, :edit, :update, :delete]

    get "/inventory", Domains.MrMunchMe.InventoryController, :index
    get "/inventory/purchases/new", Domains.MrMunchMe.InventoryController, :new_purchase
    post "/inventory/purchases", Domains.MrMunchMe.InventoryController, :create_purchase
    get "/inventory/purchases/:id/edit", Domains.MrMunchMe.InventoryController, :edit_purchase
    put "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :update_purchase
    delete "/inventory/purchases/:id", Domains.MrMunchMe.InventoryController, :delete_purchase

    post "/inventory/purchases/:id/return",
         Domains.MrMunchMe.InventoryController,
         :return_purchase

    get "/inventory/movements/new", Domains.MrMunchMe.InventoryController, :new_movement
    post "/inventory/movements", Domains.MrMunchMe.InventoryController, :create_movement
    get "/inventory/movements/:id/edit", Domains.MrMunchMe.InventoryController, :edit_movement
    put "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :update_movement
    delete "/inventory/movements/:id", Domains.MrMunchMe.InventoryController, :delete_movement
    get "/inventory/requirements", Domains.MrMunchMe.InventoryController, :requirements

    resources "/products", Domains.MrMunchMe.ProductController,
      only: [:index, :new, :create, :edit, :update, :delete]

    patch "/products/:id/toggle_active", Domains.MrMunchMe.ProductController, :toggle_active
    patch "/products/:id/move_up", Domains.MrMunchMe.ProductController, :move_up
    patch "/products/:id/move_down", Domains.MrMunchMe.ProductController, :move_down

    post "/products/:product_id/images",
         Domains.MrMunchMe.ProductController,
         :upload_gallery_image

    delete "/products/:product_id/images/:image_id",
           Domains.MrMunchMe.ProductController,
           :delete_gallery_image

    resources "/products/:product_id/variants", Domains.MrMunchMe.VariantController,
      only: [:new, :create, :edit, :update, :delete]

    post "/products/:product_id/variants/:variant_id/recipe",
         Domains.MrMunchMe.VariantController,
         :save_recipe

    resources "/discount-codes", Domains.MrMunchMe.DiscountCodeController,
      only: [:index, :new, :create, :edit, :update, :delete]

    patch "/discount-codes/:id/toggle-active",
          Domains.MrMunchMe.DiscountCodeController,
          :toggle_active

    resources "/ingredients", Domains.MrMunchMe.IngredientController,
      only: [:index, :new, :create, :edit, :update, :delete]

    resources "/recipes", Domains.MrMunchMe.RecipeController,
      only: [:index, :new, :create, :show, :edit, :delete]

    post "/recipes/new_version/:id", Domains.MrMunchMe.RecipeController, :create_new_version

    # Inventory reconciliation (MrMunchMe-specific)
    get "/reconciliation/inventory", ReconciliationController, :inventory_index
    post "/reconciliation/inventory/adjust", ReconciliationController, :inventory_adjust

    post "/reconciliation/inventory/reconcile_all",
         ReconciliationController,
         :inventory_reconcile_all

    post "/reconciliation/inventory/quick_transfer",
         ReconciliationController,
         :inventory_quick_transfer
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

      delete "/loyalty_programs/:loyalty_program_id",
             Domains.Viaxe.LoyaltyProgramController,
             :delete
    end

    # Trips (umbrella container for related bookings)
    resources "/trips", Domains.Viaxe.TripController
    get "/trips/:id/calendar", Domains.Viaxe.TripController, :calendar

    # Bookings (with type-specific details)
    resources "/bookings", Domains.Viaxe.BookingController,
      only: [:index, :show, :new, :create, :edit, :update, :delete]

    post "/bookings/:id/status", Domains.Viaxe.BookingController, :update_status

    # Services catalog
    resources "/services", Domains.Viaxe.ServiceController,
      only: [:index, :new, :create, :edit, :update, :delete]

    # Suppliers (with location info)
    resources "/suppliers", Domains.Viaxe.SupplierController

    # Recommendations (curated reference by city)
    resources "/recommendations", Domains.Viaxe.RecommendationController

    # Travel documents overview (all passports, visas, loyalty programs)
    get "/documents", Domains.Viaxe.DocumentController, :index
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

    # `/` is served by the domain's own controller. Declared BEFORE
    # core_routes_no_customers() so it wins the match — the macro's
    # ReportController dashboard route is shadowed and goes away with the
    # macro itself once the accounting surface is removed.
    get "/", Domains.HelloDoctor.DashboardController, :index

    core_routes_no_customers()

    # Conversations (all WhatsApp conversations, including those without consultations)
    # Download must come BEFORE the resources block so its literal path segment
    # isn't captured as `:id` by the `:show` route.
    get "/conversations/download",
        Domains.HelloDoctor.ConversationListController,
        :download

    resources "/conversations", Domains.HelloDoctor.ConversationListController,
      only: [:index, :show]

    # Quality feedback + live operator case note (bot ADR-059) — both
    # write through the bot's admin API, nothing stored ledgr-side.
    post "/conversations/:id/feedback",
         Domains.HelloDoctor.ConversationListController,
         :update_feedback

    post "/conversations/:id/operator-notes",
         Domains.HelloDoctor.ConversationListController,
         :update_operator_notes

    # Doctor assistant chats
    resources "/doctor-chats", Domains.HelloDoctor.DoctorChatController, only: [:index, :show]

    # Consultations (read-only — bot creates consultations)
    # Download route comes BEFORE resources so its literal segment isn't
    # captured by the `:show` :id parameter.
    get "/consultations/download",
        Domains.HelloDoctor.ConsultationController,
        :download

    resources "/consultations", Domains.HelloDoctor.ConsultationController, only: [:index, :show]
    post "/consultations/:id/status", Domains.HelloDoctor.ConsultationController, :update_status

    post "/consultations/:id/toggle-pay-doctor",
         Domains.HelloDoctor.ConsultationController,
         :toggle_pay_doctor

    resources "/reviews", Domains.HelloDoctor.ReviewController, only: [:index]

    # Review inbox — conversations awaiting quality review, priority-sorted
    # by the bot's auto-hint. Marking happens on the conversation detail page.
    get "/triage", Domains.HelloDoctor.TriageController, :index

    # Doctors (read-only — bot manages doctors)
    resources "/doctors", Domains.HelloDoctor.DoctorController,
      only: [:index, :show, :new, :create, :edit, :update]

    post "/doctors/:id/toggle-status", Domains.HelloDoctor.DoctorController, :toggle_status

    post "/doctors/:id/toggle-deactivation",
         Domains.HelloDoctor.DoctorController,
         :toggle_deactivation

    post "/doctors/:id/toggle-rfc",
         Domains.HelloDoctor.DoctorController,
         :toggle_correct_rfc

    post "/doctors/:id/provision-medikit",
         Domains.HelloDoctor.DoctorController,
         :provision_medikit

    # Patients (mostly bot-managed; the admin UI can edit a curated subset
    # of demographic fields — see Patient.editable_fields/0).
    post "/patients/recompute-tiers", Domains.HelloDoctor.PatientController, :recompute_tiers

    resources "/patients", Domains.HelloDoctor.PatientController,
      only: [:index, :show, :edit, :update]

    # Payments (queries consultations with payment data)
    resources "/payments", Domains.HelloDoctor.PaymentController, only: [:index, :show]
    post "/payments/sync", Domains.HelloDoctor.PaymentController, :sync
    post "/payments/sync-payouts", Domains.HelloDoctor.PaymentController, :sync_payouts
    post "/payments/backfill-gl", Domains.HelloDoctor.PaymentController, :backfill_gl
    post "/payments/backfill-fees", Domains.HelloDoctor.PaymentController, :backfill_fees

    post "/payments/backfill-discounts",
         Domains.HelloDoctor.PaymentController,
         :backfill_discounts

    post "/payments/:id/refund", Domains.HelloDoctor.PaymentController, :refund

    post "/payments/:id/toggle-pay-doctor",
         Domains.HelloDoctor.PaymentController,
         :toggle_pay_doctor

    post "/payments/:id/check-status", Domains.HelloDoctor.PaymentController, :check_status
    get "/payments/:id/link", Domains.HelloDoctor.PaymentController, :link_form
    post "/payments/:id/link", Domains.HelloDoctor.PaymentController, :save_link
    post "/payments/:id/unlink", Domains.HelloDoctor.PaymentController, :unlink

    # Specialties — synced from Prescrypto catalog on every page load
    resources "/specialties", Domains.HelloDoctor.SpecialtyController, only: [:index, :delete]

    patch "/specialties/:id/toggle", Domains.HelloDoctor.SpecialtyController, :toggle

    # FX rate setting
    post "/settings/fx-rate", Domains.HelloDoctor.DashboardController, :update_fx_rate

    # External billing sync + GL posting
    post "/billing/sync-costs", Domains.HelloDoctor.DashboardController, :sync_costs
    post "/billing/post-all-costs", Domains.HelloDoctor.DoctorPayoutController, :post_all_costs
    post "/billing/post-cost/:id", Domains.HelloDoctor.DoctorPayoutController, :post_cost

    # Doctor payout report
    get "/doctor-payouts", Domains.HelloDoctor.DoctorPayoutController, :index

    # Bulk CSV upload — must come BEFORE :doctor_id route so the literal
    # path segment isn't captured as a doctor_id.
    get "/doctor-payouts/bulk-upload",
        Domains.HelloDoctor.DoctorPayoutController,
        :bulk_upload_form

    post "/doctor-payouts/bulk-upload",
         Domains.HelloDoctor.DoctorPayoutController,
         :bulk_upload_submit

    get "/doctor-payouts/bulk-template",
        Domains.HelloDoctor.DoctorPayoutController,
        :bulk_template

    post "/doctor-payouts/record-payout",
         Domains.HelloDoctor.DoctorPayoutController,
         :record_payout

    # Edit / update an existing payout
    get "/doctor-payouts/:id/edit",
        Domains.HelloDoctor.DoctorPayoutController,
        :edit

    post "/doctor-payouts/:id/update",
         Domains.HelloDoctor.DoctorPayoutController,
         :update

    # Weekly consultations & payout report
    get "/reports/monthly", Domains.HelloDoctor.MonthlyReportController, :index
    get "/reports/monthly/download", Domains.HelloDoctor.MonthlyReportController, :download
    get "/reports/monthly/xlsx", Domains.HelloDoctor.MonthlyReportController, :download_xlsx

    # Bulk "mark month as paid": GET preview + POST confirm
    get "/reports/monthly/mark-paid",
        Domains.HelloDoctor.MonthlyReportController,
        :mark_paid_preview

    post "/reports/monthly/mark-paid", Domains.HelloDoctor.MonthlyReportController, :mark_paid

    # A/B experiment tracker (Scientist framework) — registry + per-arm readout
    get "/experiments", Domains.HelloDoctor.ExperimentController, :index
    get "/experiments/:id", Domains.HelloDoctor.ExperimentController, :show

    # NPS tracker (post-consultation survey responses)
    get "/nps", Domains.HelloDoctor.NpsController, :index

    # Acquisition / Meta ad attribution dashboard
    get "/acquisition", Domains.HelloDoctor.AcquisitionController, :index

    # Lifecycle conversion + unit economics (CPL / CAC / LTV)
    get "/unit-economics/download", Domains.HelloDoctor.LifecycleController, :download
    get "/unit-economics", Domains.HelloDoctor.LifecycleController, :index

    # Marketing costs (ad spend) — CSV upload + GL posting.
    # Literal paths BEFORE the :id delete route.
    get "/marketing-costs/bulk-upload",
        Domains.HelloDoctor.MarketingCostController,
        :bulk_upload_form

    post "/marketing-costs/bulk-upload",
         Domains.HelloDoctor.MarketingCostController,
         :bulk_upload_submit

    get "/marketing-costs/template", Domains.HelloDoctor.MarketingCostController, :bulk_template
    get "/marketing-costs", Domains.HelloDoctor.MarketingCostController, :index
    delete "/marketing-costs/:id", Domains.HelloDoctor.MarketingCostController, :delete

    # Doctor news blast — compose + server-side proxy to the bot's
    # /admin/doctors/broadcast-news (keeps the admin API key off the browser)
    get "/doctor-news", Domains.HelloDoctor.DoctorNewsController, :index
    get "/doctor-news/recipients", Domains.HelloDoctor.DoctorNewsController, :recipients
    post "/doctor-news/preview", Domains.HelloDoctor.DoctorNewsController, :preview
    post "/doctor-news/send", Domains.HelloDoctor.DoctorNewsController, :send

    # Corporate accounts admin (proxies the bot's /admin/corporate API)
    get "/corporate", Domains.HelloDoctor.CorporateController, :index
    get "/corporate/new", Domains.HelloDoctor.CorporateController, :new
    post "/corporate", Domains.HelloDoctor.CorporateController, :create
    get "/corporate/:slug", Domains.HelloDoctor.CorporateController, :show

    post "/corporate/:slug/update",
         Domains.HelloDoctor.CorporateController,
         :update

    post "/corporate/:slug/toggle-status",
         Domains.HelloDoctor.CorporateController,
         :toggle_status

    post "/corporate/:slug/members",
         Domains.HelloDoctor.CorporateController,
         :add_members

    post "/corporate/:slug/members/:phone/remove",
         Domains.HelloDoctor.CorporateController,
         :remove_member

    get "/corporate/:slug/invoice", Domains.HelloDoctor.CorporateController, :invoice

    get "/corporate/:slug/invoice/download",
        Domains.HelloDoctor.CorporateController,
        :invoice_csv

    post "/corporate/:slug/invoice/settle",
         Domains.HelloDoctor.CorporateController,
         :settle_invoice
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

    # No core_routes_* here: this domain posts nothing to the general ledger,
    # so it routes none of the accounting surface. Same shape as Escuela de
    # Dinero. `menu_items/0` is therefore the only way to reach a page.
    get "/", Domains.AumentaMiPension.DashboardController, :index

    # Conversations + their operator buckets as CSV. Must come BEFORE the
    # resources block so "download" isn't captured as `:id` by `:show`.
    get "/conversations/download",
        Domains.AumentaMiPension.ConversationListController,
        :download

    resources "/conversations", Domains.AumentaMiPension.ConversationListController,
      only: [:index, :show]

    # Operator tags ("buckets") for a conversation — Ledgr-owned overlay,
    # auto-saved from the checkbox card on the conversation detail page.
    post "/conversations/:id/buckets",
         Domains.AumentaMiPension.ConversationListController,
         :update_buckets

    # Unified leads view (joins conversations / checkup / calculadora by phone).
    # CRM annotations live here at the lead level, not per-conversation.
    get "/leads", Domains.AumentaMiPension.LeadController, :index
    get "/leads/:phone", Domains.AumentaMiPension.LeadController, :show
    post "/leads/:phone/crm", Domains.AumentaMiPension.LeadController, :update_crm

    # Live data-quality dashboard: lead coverage vs. AFORE traspaso requirements.
    get "/traspaso-coverage", Domains.AumentaMiPension.TraspasoCoverageController, :index
    get "/traspaso-coverage/export", Domains.AumentaMiPension.TraspasoCoverageController, :export

    resources "/agent-chats", Domains.AumentaMiPension.AgentChatController, only: [:index, :show]

    resources "/consultations", Domains.AumentaMiPension.ConsultationController,
      only: [:index, :show]

    post "/consultations/:id/status",
         Domains.AumentaMiPension.ConsultationController,
         :update_status

    resources "/agents", Domains.AumentaMiPension.AgentController,
      only: [:index, :show, :new, :create, :edit, :update]

    post "/agents/:id/toggle-status", Domains.AumentaMiPension.AgentController, :toggle_status

    resources "/customers", Domains.AumentaMiPension.CustomerController, only: [:index, :show]
    post "/customers/:id/reset", Domains.AumentaMiPension.CustomerController, :reset

    resources "/pension-cases", Domains.AumentaMiPension.PensionCaseController,
      only: [:index, :show]

    resources "/calculadora", Domains.AumentaMiPension.CalculadoraController,
      only: [:index, :show]

    resources "/checkup", Domains.AumentaMiPension.CheckupController, only: [:index, :show]

    resources "/payments", Domains.AumentaMiPension.PaymentController, only: [:index, :show]
    post "/payments/sync", Domains.AumentaMiPension.PaymentController, :sync
    post "/payments/:id/refund", Domains.AumentaMiPension.PaymentController, :refund
    post "/payments/:id/check-status", Domains.AumentaMiPension.PaymentController, :check_status
    get "/payments/:id/link", Domains.AumentaMiPension.PaymentController, :link_form
    post "/payments/:id/link", Domains.AumentaMiPension.PaymentController, :save_link
    post "/payments/:id/unlink", Domains.AumentaMiPension.PaymentController, :unlink
  end

  # ── Escuela de Dinero: public auth routes ──────────────────────────
  scope "/app/escuela-de-dinero", LedgrWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # ── Escuela de Dinero: protected routes ────────────────────────────
  #
  # Operational-only domain: deliberately NO `core_routes*` macro, no
  # ReportController, no accounting. `/` is our own DashboardController.
  # That's safe because implementing `nav_icons/0` suppresses the shared
  # Reports/Reconciliation/Other nav groups in root.html.heex — which also
  # means `menu_items/0` is the sole source of navigation here.
  #
  # Every route is a GET. The bot owns this database; Ledgr only reads it.
  scope "/app/escuela-de-dinero", LedgrWeb do
    pipe_through [:browser, :require_auth]

    get "/", Domains.EscuelaDeDinero.DashboardController, :index

    resources "/personas", Domains.EscuelaDeDinero.PersonController, only: [:index, :show]

    resources "/diagnosticos", Domains.EscuelaDeDinero.DiagnosticoController,
      only: [:index, :show]

    get "/movimientos", Domains.EscuelaDeDinero.MovimientoController, :index

    resources "/conversaciones", Domains.EscuelaDeDinero.ConversationController,
      only: [:index, :show]

    get "/calidad", Domains.EscuelaDeDinero.CalidadController, :index
    get "/kubo", Domains.EscuelaDeDinero.KuboController, :index
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
