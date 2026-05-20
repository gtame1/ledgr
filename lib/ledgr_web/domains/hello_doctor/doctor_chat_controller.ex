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

  def show(conn, %{"id" => doctor_id}) do
    {doctor, messages} = DoctorAssistantMessages.get_doctor_thread!(doctor_id)

    # Messages already come back chronologically ascending from the context.
    # Compute distinct consultations referenced (excluding nil) for the header.
    consultation_count =
      messages
      |> Enum.map(& &1.consultation_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> length()

    render(conn, :show,
      doctor: doctor,
      messages: messages,
      consultation_count: consultation_count
    )
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorChatHTML do
  use LedgrWeb, :html
  embed_templates "doctor_chat_html/*"
end
