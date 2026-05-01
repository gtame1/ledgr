defmodule LedgrWeb.TransactionController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting
  alias Ledgr.Core.Accounting.JournalEntry
  alias LedgrWeb.Helpers.MoneyHelper

  def index(conn, _params) do
    entries = Accounting.list_journal_entries()

    template =
      if Ledgr.Domain.current() == Ledgr.Domains.HelloDoctor,
        do: :hello_doctor_index,
        else: :index

    render(conn, template,
      page_title: "Transactions",
      entries: entries
    )
  end

  def new(conn, _params) do
    template =
      if Ledgr.Domain.current() == Ledgr.Domains.HelloDoctor,
        do: :hello_doctor_new,
        else: :new

    render(conn, template,
      page_title: "New Transaction",
      changeset: Accounting.change_journal_entry(%JournalEntry{}),
      account_options: Accounting.account_select_options(),
      entry_types: JournalEntry.entry_types(),
      action: dp(conn, "/transactions")
    )
  end

  def create(conn, %{"journal_entry" => entry_params}) do
    # Convert pesos to cents for journal lines
    entry_params =
      entry_params
      |> MoneyHelper.convert_nested_params_pesos_to_cents("journal_lines", [
        :debit_cents,
        :credit_cents
      ])

    case Accounting.create_journal_entry(entry_params) do
      {:ok, entry} ->
        conn
        |> put_flash(:info, "Transaction recorded.")
        |> redirect(to: dp(conn, "/transactions/#{entry.id}"))

      {:error, %Ecto.Changeset{} = changeset} ->
        # Mark changeset as having an attempted action so errors show in UI
        changeset = Map.put(changeset, :action, :insert)
        IO.inspect(changeset.errors, label: "Root Errors")
        IO.inspect(changeset.changes.journal_lines, label: "Line Changesets")

        render(conn, :new,
          page_title: "New Transaction",
          changeset: changeset,
          action: dp(conn, "/transactions"),
          account_options: Accounting.account_select_options(),
          entry_types: JournalEntry.entry_types()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    entry = Accounting.get_journal_entry!(id)

    render(conn, :show,
      page_title: "Transaction",
      entry: entry
    )
  end
end

defmodule LedgrWeb.TransactionHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents
  alias LedgrWeb.Helpers.MoneyHelper

  embed_templates "transaction_html/*"
end
