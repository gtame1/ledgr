defmodule LedgrWeb.Domains.AumentaMiPension.AgentController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.AumentaMiPension.Agents

  def index(conn, params) do
    agents =
      Agents.list_agents(
        status: params["status"],
        search: params["search"]
      )

    render(conn, :index,
      agents: agents,
      current_status: params["status"],
      current_search: params["search"]
    )
  end

  def show(conn, %{"id" => id}) do
    agent = Agents.get_agent!(id)

    render(conn, :show, agent: agent)
  end

  def new(conn, _params) do
    changeset = Agents.change_agent(%Ledgr.Domains.AumentaMiPension.Agents.Agent{})

    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"agent" => agent_params}) do
    case Agents.create_agent(agent_params) do
      {:ok, agent} ->
        conn
        |> put_flash(:info, "Agente creado exitosamente.")
        |> redirect(to: dp(conn, "/agents/#{agent.id}"))

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    agent = Agents.get_agent!(id)
    changeset = Agents.change_agent(agent)

    render(conn, :edit, agent: agent, changeset: changeset)
  end

  def update(conn, %{"id" => id, "agent" => agent_params}) do
    agent = Agents.get_agent!(id)

    case Agents.update_agent(agent, agent_params) do
      {:ok, agent} ->
        conn
        |> put_flash(:info, "Agente actualizado exitosamente.")
        |> redirect(to: dp(conn, "/agents/#{agent.id}"))

      {:error, changeset} ->
        render(conn, :edit, agent: agent, changeset: changeset)
    end
  end

  def toggle_status(conn, %{"id" => id}) do
    agent = Agents.get_agent!(id)

    case Agents.toggle_availability(agent) do
      {:ok, agent} ->
        status_label = if agent.is_available, do: "disponible", else: "no disponible"

        conn
        |> put_flash(:info, "Agente ahora está #{status_label}.")
        |> redirect(to: dp(conn, "/agents/#{agent.id}"))

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {k, v}, acc ->
            String.replace(acc, "%{#{k}}", to_string(v))
          end)
        end)
        conn
        |> put_flash(:error, "Failed to update availability: #{inspect(errors)}")
        |> redirect(to: dp(conn, "/agents/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.AumentaMiPension.AgentHTML do
  use LedgrWeb, :html
  embed_templates "agent_html/*"
end
