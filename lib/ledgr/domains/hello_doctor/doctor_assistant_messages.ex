defmodule Ledgr.Domains.HelloDoctor.DoctorAssistantMessages do
  import Ecto.Query, warn: false
  alias Ledgr.Repo
  alias Ledgr.Domains.HelloDoctor.DoctorAssistantMessages.DoctorAssistantMessage
  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor

  @doc """
  Returns one summary row per doctor: doctor info, message count, last message time.
  Optionally filter by doctor name search.
  """
  def list_by_doctor(opts \\ []) do
    search = opts[:search]

    query =
      from d in Doctor,
        join: m in DoctorAssistantMessage, on: m.doctor_id == d.id,
        group_by: d.id,
        select: %{
          doctor_id: d.id,
          doctor_name: d.name,
          doctor_specialty: d.specialty,
          doctor_available: d.is_available,
          message_count: count(m.id),
          last_message_at: max(m.created_at)
        },
        order_by: [desc: max(m.created_at)]

    query =
      if search && search != "" do
        term = "%#{search}%"
        where(query, [d, _m], ilike(d.name, ^term))
      else
        query
      end

    Repo.all(query)
  end

  @doc "Returns all messages for a doctor, sorted chronologically."
  def list_for_doctor(doctor_id, opts \\ []) do
    consultation_id = opts[:consultation_id]

    query =
      DoctorAssistantMessage
      |> where([m], m.doctor_id == ^doctor_id)
      |> order_by([m], asc: m.created_at)

    query =
      if consultation_id do
        where(query, [m], m.consultation_id == ^consultation_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc "Returns the doctor with their assistant messages, grouped by consultation."
  def get_doctor_thread!(doctor_id) do
    doctor = Repo.get!(Doctor, doctor_id)

    messages =
      DoctorAssistantMessage
      |> where([m], m.doctor_id == ^doctor_id)
      |> order_by([m], asc: m.created_at)
      |> Repo.all()

    {doctor, messages}
  end

  @doc "Distinct consultation IDs for a doctor's messages (excluding nil)."
  def consultation_ids_for_doctor(doctor_id) do
    DoctorAssistantMessage
    |> where([m], m.doctor_id == ^doctor_id and not is_nil(m.consultation_id))
    |> select([m], m.consultation_id)
    |> distinct(true)
    |> Repo.all()
  end
end
