defmodule LedgrWeb.Domains.Viaxe.DocumentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.Viaxe.{TravelDocuments, Customers}
  alias Ledgr.Domains.Viaxe.TravelDocuments.{Passport, Visa, LoyaltyProgram}

  def index(conn, _params) do
    passports = TravelDocuments.list_passports()
    visas = TravelDocuments.list_visas()
    loyalty_programs = TravelDocuments.list_loyalty_programs()
    customers = Customers.list_customers()

    render(conn, :index,
      passports: passports,
      visas: visas,
      loyalty_programs: loyalty_programs,
      customers: customers,
      passport_changeset: TravelDocuments.change_passport(%Passport{}),
      visa_changeset: TravelDocuments.change_visa(%Visa{}),
      loyalty_changeset: TravelDocuments.change_loyalty_program(%LoyaltyProgram{}),
      today: today_mx()
    )
  end
end

defmodule LedgrWeb.Domains.Viaxe.DocumentHTML do
  use LedgrWeb, :html

  alias Ledgr.Domains.Viaxe.Customers.Customer

  embed_templates "document_html/*"

  def full_name(customer), do: Customer.full_name(customer)

  # Returns :expired, :expiring_soon, or :ok
  def expiry_status(nil, _today), do: :ok
  def expiry_status(expiry_date, today) do
    cond do
      Date.compare(expiry_date, today) == :lt        -> :expired
      Date.diff(expiry_date, today) <= 180            -> :expiring_soon
      true                                            -> :ok
    end
  end
end
