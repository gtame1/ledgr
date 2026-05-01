defmodule Ledgr.Domains.CasaTame.Bills.RecurringBill do
  use Ecto.Schema
  import Ecto.Changeset

  @frequencies ~w(monthly biweekly weekly quarterly annual one_time)
  @categories ~w(credit_card utility loan insurance subscription other)

  schema "recurring_bills" do
    field :name, :string
    field :amount_cents, :integer
    field :currency, :string, default: "MXN"
    field :frequency, :string
    field :day_of_month, :integer
    field :next_due_date, :date
    field :category, :string
    field :notes, :string
    field :is_active, :boolean, default: true
    field :last_paid_date, :date

    timestamps()
  end

  def changeset(bill, attrs) do
    bill
    |> cast(attrs, [
      :name,
      :amount_cents,
      :currency,
      :frequency,
      :day_of_month,
      :next_due_date,
      :category,
      :notes,
      :is_active,
      :last_paid_date
    ])
    |> validate_required([:name, :frequency, :next_due_date])
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_inclusion(:currency, ["USD", "MXN"])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:day_of_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:amount_cents, greater_than: 0)
  end

  def frequency_options do
    [
      {"Monthly", "monthly"},
      {"Bi-weekly", "biweekly"},
      {"Weekly", "weekly"},
      {"Quarterly", "quarterly"},
      {"Annual", "annual"},
      {"One-time", "one_time"}
    ]
  end

  def category_options do
    [
      {"Credit Card", "credit_card"},
      {"Utility", "utility"},
      {"Loan", "loan"},
      {"Insurance", "insurance"},
      {"Subscription", "subscription"},
      {"Other", "other"}
    ]
  end

  def category_color(category) do
    case category do
      "credit_card" -> "#dc2626"
      "utility" -> "#2563eb"
      "loan" -> "#ea580c"
      "insurance" -> "#7c3aed"
      "subscription" -> "#0d9488"
      _ -> "#6b7280"
    end
  end
end
