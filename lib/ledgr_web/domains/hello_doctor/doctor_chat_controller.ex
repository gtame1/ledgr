defmodule LedgrWeb.Domains.HelloDoctor.DoctorChatController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.DoctorAssistantMessages

  def index(conn, params) do
    threads = DoctorAssistantMessages.list_by_doctor(search: params["search"])

    render(conn, :index,
      threads: threads,
      current_search: params["search"] || ""
    )
  end

  def show(conn, %{"id" => doctor_id} = params) do
    {doctor, messages} = DoctorAssistantMessages.get_doctor_thread!(doctor_id)

    # Group messages by consultation_id (nil = general chat)
    grouped =
      messages
      |> Enum.group_by(& &1.consultation_id)
      |> Enum.sort_by(fn {_k, msgs} -> List.first(msgs).created_at end)

    render(conn, :show,
      doctor: doctor,
      grouped_messages: grouped,
      current_filter: params["consultation_id"]
    )
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorChatHTML do
  use LedgrWeb, :html
  embed_templates "doctor_chat_html/*"
end
