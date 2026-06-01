defmodule LedgrWeb.Domains.HelloDoctor.ConsultationController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Consultations
  alias Ledgr.Domains.HelloDoctor.ConsultationFunnelExport
  alias Ledgr.Domains.HelloDoctor.ConsultationPayoutDecisions

  def index(conn, params) do
    filters = %{
      status: params["status"],
      search: params["search"]
    }

    consultations = Consultations.list_consultations(filters)

    render(conn, :index,
      consultations: consultations,
      current_status: params["status"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    consultation = Consultations.get_consultation!(id)
    decision = ConsultationPayoutDecisions.get(id)

    render(conn, :show,
      consultation: consultation,
      pay_doctor: if(decision, do: decision.pay_doctor, else: true),
      payout_decision: decision
    )
  end

  @doc """
  Flips the pay-doctor decision for this consultation. Same semantics
  as the payment-show toggle, but keyed off the consultation so it
  works for 100% discount consultations that have no Stripe payment.
  Ledger is not touched — operator posts a manual JE if needed.
  """
  def toggle_pay_doctor(conn, %{"id" => id}) do
    current = ConsultationPayoutDecisions.pay_doctor?(id)
    new_value = not current

    case ConsultationPayoutDecisions.upsert(id, new_value,
           reason: "manual override via consultation page",
           decided_by: "admin"
         ) do
      {:ok, _} ->
        msg =
          if new_value,
            do:
              "Doctor flagged as payable for this consultation. " <>
                "Reports will now include it — post a manual JE if the ledger needs to match.",
            else:
              "Doctor flagged as NOT payable. Reports will skip this consultation. " <>
                "Post a manual JE if the ledger needs to match."

        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/consultations/#{id}"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to toggle pay-doctor: #{inspect(changeset.errors)}")
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end

  @doc """
  Streams the consultation funnel summary as a CSV download. Filter params
  mirror the index page (status / search).
  """
  def download(conn, params) do
    try do
      csv =
        ConsultationFunnelExport.to_csv(
          status: params["status"],
          search: params["search"],
          limit: params["limit"]
        )

      today = Ledgr.Domains.HelloDoctor.today()
      filename = "hello-doctor-consultations-#{today}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    rescue
      e in Postgrex.Error ->
        # Bot-owned columns / tables may drift faster than our schemas. Surface
        # a short reason inline; full message goes to logs.
        require Logger

        Logger.error("[HelloDoctor] Consultation funnel export failed: #{Exception.message(e)}")

        short =
          case e.postgres do
            %{message: msg} -> msg
            _ -> "database error"
          end
          |> to_string()
          |> String.slice(0, 200)

        conn
        |> put_flash(:error, "Couldn't generate the consultations CSV: #{short}")
        |> redirect(to: dp(conn, "/consultations"))
    end
  end

  def update_status(conn, %{"id" => id, "status" => status}) do
    consultation = Consultations.get_consultation!(id)

    case Consultations.update_consultation(consultation, %{status: status}) do
      {:ok, consultation} ->
        conn
        |> put_flash(:info, "Status updated to #{status}.")
        |> redirect(to: dp(conn, "/consultations/#{consultation.id}"))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update status.")
        |> redirect(to: dp(conn, "/consultations/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.ConsultationHTML do
  use LedgrWeb, :html
  embed_templates "consultation_html/*"
end
