defmodule LedgrWeb.TransferController do
  use LedgrWeb, :controller

  alias Ledgr.Core.Accounting

  def index(conn, _params) do
    transfers = Accounting.list_money_transfers()

    # Casa Tame: also show FX transfers (journal entries with "FX Transfer" in description)
    extra =
      if Ledgr.Domain.current() == Ledgr.Domains.CasaTame do
        import Ecto.Query
        fx = Ledgr.Repo.all(
          from je in Ledgr.Core.Accounting.JournalEntry,
            where: je.entry_type == "internal_transfer" and like(je.description, "FX Transfer%"),
            order_by: [desc: je.date, desc: je.inserted_at],
            preload: [journal_lines: :account],
            limit: 50
        )
        [fx_transfers: fx]
      else
        []
      end

    render(conn, :index, [transfers: transfers] ++ extra)
  end

  def new(conn, _params) do
    changeset = Accounting.change_transfer_form(%{})

    render(conn, :new,
      changeset: changeset,
      account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def create(conn, %{"transfer" => params}) do
    case Accounting.create_money_transfer(params) do
      {:ok, transfer} ->
        conn
        |> put_flash(:info, "Transfer recorded successfully.")
        |> redirect(to: dp(conn, "/transfers/#{transfer.id}"))

      {:error, changeset} ->
        changeset = %{changeset | action: :insert}

        render(conn, :new,
          changeset: changeset,
          account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end

  def show(conn, %{"id" => id}) do
    transfer = Accounting.get_money_transfer!(id)

    render(conn, :show, transfer: transfer)
  end

  def edit(conn, %{"id" => id}) do
    transfer = Accounting.get_money_transfer!(id)

    # Convert amount_cents to pesos for form display
    amount_pesos = Decimal.div(Decimal.new(transfer.amount_cents), Decimal.new(100)) |> Decimal.to_float()

    attrs = %{
      "from_account_id" => transfer.from_account_id,
      "to_account_id" => transfer.to_account_id,
      "date" => transfer.date,
      "amount_pesos" => amount_pesos,
      "note" => transfer.note
    }

    changeset = Accounting.change_transfer_form(attrs)

    render(conn, :edit,
      transfer: transfer,
      changeset: changeset,
      account_options: Accounting.cash_or_payable_account_options()
    )
  end

  def update(conn, %{"id" => id, "transfer" => params}) do
    transfer = Accounting.get_money_transfer!(id)

    case Accounting.update_money_transfer(transfer, params) do
      {:ok, transfer} ->
        conn
        |> put_flash(:info, "Transfer updated successfully.")
        |> redirect(to: dp(conn, "/transfers/#{transfer.id}"))

      {:error, changeset} ->
        changeset = %{changeset | action: :update}

        render(conn, :edit,
          transfer: transfer,
          changeset: changeset,
          account_options: Accounting.cash_or_payable_account_options()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    transfer = Accounting.get_money_transfer!(id)

    case Accounting.delete_money_transfer(transfer) do
      {:ok, _transfer} ->
        conn
        |> put_flash(:info, "Transfer deleted successfully.")
        |> redirect(to: dp(conn, "/transfers"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete transfer.")
        |> redirect(to: dp(conn, "/transfers/#{transfer.id}"))
    end
  end
end


defmodule LedgrWeb.TransferHTML do
  use LedgrWeb, :html
  import LedgrWeb.CoreComponents

  embed_templates "transfer_html/*"
end
