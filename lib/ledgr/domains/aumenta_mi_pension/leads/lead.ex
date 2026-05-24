defmodule Ledgr.Domains.AumentaMiPension.Leads.Lead do
  @moduledoc """
  Read-side projection of an AMP lead — everything we know about a
  single phone number across the three sources (`customers`,
  `checkup_responses`, `calculadora_submissions`) plus the operator
  overlay (`lead_crm`).

  **Not an Ecto schema.** Assembled per-request by the `Leads` context;
  never persisted. The persisted identity is the normalized `phone` —
  this struct just bundles the records we joined to it.
  """

  @type t :: %__MODULE__{
          phone: String.t(),
          display_name: String.t() | nil,
          sources: MapSet.t(:conversation | :checkup | :calculadora),
          customer: Ledgr.Domains.AumentaMiPension.Customers.Customer.t() | nil,
          conversations: [struct()],
          checkup_responses: [struct()],
          calculadora_submissions: [struct()],
          crm_entry: Ledgr.Domains.AumentaMiPension.CrmEntries.CrmEntry.t() | nil,
          last_activity_at: DateTime.t() | NaiveDateTime.t() | nil,
          latest_conversation: struct() | nil
        }

  defstruct phone: nil,
            display_name: nil,
            sources: MapSet.new(),
            customer: nil,
            conversations: [],
            checkup_responses: [],
            calculadora_submissions: [],
            crm_entry: nil,
            last_activity_at: nil,
            latest_conversation: nil
end
