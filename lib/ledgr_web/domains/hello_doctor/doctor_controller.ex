defmodule LedgrWeb.Domains.HelloDoctor.DoctorController do
  use LedgrWeb, :controller

  alias Ledgr.Domains.HelloDoctor.Doctors

  def index(conn, params) do
    sort = params["sort"] || "name"
    dir = params["dir"] || default_dir(sort)

    filters = %{
      status: params["status"],
      search: params["search"],
      deactivated: params["deactivated"],
      sort: sort,
      dir: dir
    }

    doctors = Doctors.list_doctors(filters)

    render(conn, :index,
      doctors: doctors,
      current_status: params["status"],
      current_search: params["search"],
      current_deactivated: params["deactivated"],
      sort: sort,
      dir: dir
    )
  end

  # `eligibility` sorts descending by default — "show me who's blocked"
  # is usually the action item. Other columns default to ascending.
  defp default_dir("eligibility"), do: "desc"
  defp default_dir(_), do: "asc"

  def show(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    render(conn, :show, doctor: doctor)
  end

  def new(conn, _params) do
    changeset = Doctors.change_doctor(%Ledgr.Domains.HelloDoctor.Doctors.Doctor{})

    render(conn, :new,
      changeset: changeset,
      specialty_options: Doctors.specialty_options()
    )
  end

  def create(conn, %{"doctor" => doctor_params}) do
    case Doctors.create_doctor(doctor_params) do
      {:ok, doctor} ->
        conn =
          if is_nil(doctor.prescrypto_medic_id) do
            put_flash(
              conn,
              :warning,
              "Doctor created, but Prescrypto sync failed — retry from the doctor page."
            )
          else
            conn
          end

        conn
        |> put_flash(:info, "Doctor created successfully.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        render(conn, :new,
          changeset: changeset,
          specialty_options: Doctors.specialty_options()
        )
    end
  end

  def retry_prescrypto_sync(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Ledgr.Domains.HelloDoctor.Prescrypto.create_medic(doctor) do
      {:ok, result} ->
        # result has :prescrypto_medic_id, :prescrypto_token, :prescrypto_specialty_verified
        # Build the update map. Don't overwrite an existing token with nil (the GET
        # fallback path can't recover the token, only the medic ID + verified flag).
        updates =
          %{
            prescrypto_medic_id: result.prescrypto_medic_id,
            prescrypto_specialty_verified: result.prescrypto_specialty_verified,
            prescrypto_synced_at: DateTime.utc_now()
          }
          |> then(fn m ->
            if result.prescrypto_token,
              do: Map.put(m, :prescrypto_token, result.prescrypto_token),
              else: m
          end)

        {:ok, _} = Doctors.update_doctor(doctor, updates)

        verified_msg =
          if result.prescrypto_specialty_verified,
            do: " — cédula verified ✅",
            else: " — cédula pending verification by Prescrypto"

        conn
        |> put_flash(
          :info,
          "Prescrypto sync successful (medic ##{result.prescrypto_medic_id})#{verified_msg}."
        )
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, {:api_error, _status, errors}} ->
        conn
        |> put_flash(:error, "Prescrypto sync failed: #{format_prescrypto_errors(errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, :missing_cedula} ->
        conn
        |> put_flash(
          :error,
          "Prescrypto sync failed: this doctor has no Cédula Profesional. Add it via Edit Doctor."
        )
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, :missing_email} ->
        conn
        |> put_flash(
          :error,
          "Prescrypto sync failed: this doctor has no email address. Add it via Edit Doctor."
        )
        |> redirect(to: dp(conn, "/doctors/#{id}"))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Prescrypto sync failed: #{inspect(reason)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end

  defp format_prescrypto_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(List.wrap(msgs), ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_prescrypto_errors(other), do: inspect(other)

  def edit(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)
    changeset = Doctors.change_doctor(doctor)

    render(conn, :edit,
      doctor: doctor,
      changeset: changeset,
      specialty_options: Doctors.specialty_options()
    )
  end

  def update(conn, %{"id" => id, "doctor" => doctor_params}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.update_doctor(doctor, doctor_params) do
      {:ok, doctor} ->
        conn
        |> put_flash(:info, "Doctor updated successfully.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        render(conn, :edit,
          doctor: doctor,
          changeset: changeset,
          specialty_options: Doctors.specialty_options()
        )
    end
  end

  def toggle_status(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.toggle_availability(doctor) do
      {:ok, doctor} ->
        status_label = if doctor.is_available, do: "available", else: "unavailable"

        conn
        |> put_flash(:info, "Doctor is now #{status_label}.")
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {k, v}, acc ->
              String.replace(acc, "%{#{k}}", to_string(v))
            end)
          end)

        conn
        |> put_flash(:error, "Failed to update availability: #{inspect(errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end

  def toggle_deactivation(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.toggle_deactivation(doctor) do
      {:ok, doctor} ->
        msg =
          if doctor.deactivated_at,
            do: "Doctor deactivated — bot will not route new consultations.",
            else: "Doctor reactivated — eligible for new consultations again."

        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to toggle deactivation: #{inspect(changeset.errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end

  def toggle_correct_rfc(conn, %{"id" => id}) do
    doctor = Doctors.get_doctor!(id)

    case Doctors.toggle_correct_rfc(doctor) do
      {:ok, doctor} ->
        msg =
          if doctor.has_correct_rfc,
            do: "RFC marked as verified.",
            else: "RFC verification cleared."

        conn
        |> put_flash(:info, msg)
        |> redirect(to: dp(conn, "/doctors/#{doctor.id}"))

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to toggle RFC flag: #{inspect(changeset.errors)}")
        |> redirect(to: dp(conn, "/doctors/#{id}"))
    end
  end
end

defmodule LedgrWeb.Domains.HelloDoctor.DoctorHTML do
  use LedgrWeb, :html
  embed_templates "doctor_html/*"

  alias Ledgr.Domains.HelloDoctor.Doctors.Doctor
  alias Ledgr.Domains.HelloDoctor.Medikit
  alias Ledgr.Domains.HelloDoctor.MedikitSpecialties

  @doc "Dark switch — hides all Medikit admin UI until the env is configured."
  def medikit_enabled?, do: Medikit.enabled?()

  @doc """
  The doctor's structured name (given names + both surnames). Replaces the old
  single "Full Name" input — `Doctor.changeset/2` derives `name` from these, so
  the name is captured once. Shared by the new and edit forms.
  """
  attr :changeset, :any, required: true

  def name_fields(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-4">
      <.medikit_text changeset={@changeset} field={:first_name} label="First name(s)" required />
      <.medikit_text
        changeset={@changeset}
        field={:paternal_surname}
        label="Paternal surname"
        required
      />
      <.medikit_text changeset={@changeset} field={:maternal_surname} label="Maternal surname" />
    </div>
    """
  end

  @doc """
  The structured doctor data Medikit's doctors API needs (birthdate, gender, RFC,
  specialty catalog id, postal address). Shared by the new and edit forms. Name
  parts live in `name_fields/1` (they double as the doctor's name). Values come
  from `Ecto.Changeset.get_field/2` (works for both an unsaved and a persisted
  changeset); errors show only after a submit (`@changeset.action`).
  """
  attr :changeset, :any, required: true

  def medikit_fields(assigns) do
    assigns =
      assign(assigns,
        medikit_specialty_options: MedikitSpecialties.options(),
        genders: Doctor.genders(),
        countries: Doctor.countries(),
        mx_states: Doctor.mx_states()
      )

    ~H"""
    <div class="pt-5 mt-5" style="border-top: 1px solid var(--border-subtle);">
      <h2 class="text-sm font-semibold mb-1" style="color: var(--text-main);">
        Medikit — digital prescriptions
      </h2>
      <p class="text-xs mb-4" style="color: var(--text-muted);">
        Required to register the doctor with Medikit. All fields must be filled (and the cédula
        validated) before the doctor can be provisioned.
      </p>

      <div class="grid grid-cols-3 gap-4">
        <div>
          <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
            Birthdate
          </label>
          <input
            type="date"
            name="doctor[birthdate]"
            value={date_value(@changeset, :birthdate)}
            class="w-full rounded-lg border px-4 py-2.5 text-sm"
            style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
          />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
            Gender
          </label>
          <select
            name="doctor[gender]"
            class="w-full rounded-lg border px-4 py-2.5 text-sm"
            style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
          >
            <option value="">—</option>
            <%= for g <- @genders do %>
              <option value={g} selected={field_value(@changeset, :gender) == g}>{g}</option>
            <% end %>
          </select>
          <.medikit_error changeset={@changeset} field={:gender} />
        </div>

        <.medikit_text changeset={@changeset} field={:tax_id} label="RFC (Tax ID)" />
      </div>

      <div class="mt-4">
        <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
          Medikit specialty <span style="color: #dc2626;">*</span>
        </label>
        <select
          name="doctor[medikit_specialty_id]"
          class="w-full rounded-lg border px-4 py-2.5 text-sm"
          style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
        >
          <option value="">Select Medikit specialty...</option>
          <%= for {label, id} <- @medikit_specialty_options do %>
            <option value={id} selected={field_value(@changeset, :medikit_specialty_id) == id}>
              {label}
            </option>
          <% end %>
        </select>
        <%= if @medikit_specialty_options == [] do %>
          <p class="text-xs mt-1" style="color: #dc2626;">
            No Medikit specialty catalog configured yet — set <code>:medikit</code>
            <code>:specialty_catalog</code> once the Account Manager provides it.
          </p>
        <% end %>
      </div>

      <div class="grid grid-cols-2 gap-4 mt-4">
        <.medikit_text changeset={@changeset} field={:address_line} label="Address (street & number)" />
        <.medikit_text changeset={@changeset} field={:address_city} label="City" />
      </div>

      <div class="grid grid-cols-3 gap-4 mt-4">
        <div>
          <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
            Country
          </label>
          <select
            name="doctor[address_country]"
            class="w-full rounded-lg border px-4 py-2.5 text-sm"
            style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
          >
            <%= for c <- @countries do %>
              <option value={c} selected={country_selected?(@changeset, c)}>{c}</option>
            <% end %>
          </select>
          <.medikit_error changeset={@changeset} field={:address_country} />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
            State
          </label>
          <select
            name="doctor[address_state]"
            class="w-full rounded-lg border px-4 py-2.5 text-sm"
            style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
          >
            <option value="">—</option>
            <%= for s <- @mx_states do %>
              <option value={s} selected={field_value(@changeset, :address_state) == s}>{s}</option>
            <% end %>
          </select>
          <.medikit_error changeset={@changeset} field={:address_state} />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
            Zipcode
          </label>
          <input
            type="text"
            name="doctor[address_zipcode]"
            value={field_value(@changeset, :address_zipcode)}
            inputmode="numeric"
            class="w-full rounded-lg border px-4 py-2.5 text-sm"
            style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
            placeholder="64000"
          />
          <.medikit_error changeset={@changeset} field={:address_zipcode} />
        </div>
      </div>
    </div>
    """
  end

  attr :changeset, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :required, :boolean, default: false

  defp medikit_text(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium mb-1" style="color: var(--text-main);">
        {@label}<span :if={@required} style="color: #dc2626;"> *</span>
      </label>
      <input
        type="text"
        name={"doctor[#{@field}]"}
        value={field_value(@changeset, @field)}
        class="w-full rounded-lg border px-4 py-2.5 text-sm"
        style="background: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-main);"
      />
      <.medikit_error changeset={@changeset} field={@field} />
    </div>
    """
  end

  attr :changeset, :any, required: true
  attr :field, :atom, required: true

  defp medikit_error(assigns) do
    ~H"""
    <%= if @changeset.action && @changeset.errors[@field] do %>
      <p class="text-xs mt-1" style="color: #dc2626;">{elem(@changeset.errors[@field], 0)}</p>
    <% end %>
    """
  end

  defp field_value(changeset, field), do: Ecto.Changeset.get_field(changeset, field) || ""

  # Country defaults to "MX" in the dropdown when the doctor has none set yet.
  defp country_selected?(changeset, country) do
    case Ecto.Changeset.get_field(changeset, :address_country) do
      nil -> country == "MX"
      "" -> country == "MX"
      v -> v == country
    end
  end

  defp date_value(changeset, field) do
    case Ecto.Changeset.get_field(changeset, field) do
      %Date{} = d -> Date.to_iso8601(d)
      _ -> ""
    end
  end

  @doc """
  Builds the query string for a doctor-list URL with the given overrides
  layered on top of the current filter/sort state. Drops empty/nil values
  so the URL stays tidy.
  """
  def doctors_query(assigns, overrides) do
    base = %{
      "status" => assigns.current_status,
      "search" => assigns.current_search,
      "deactivated" => assigns.current_deactivated,
      "sort" => assigns.sort,
      "dir" => assigns.dir
    }

    base
    |> Map.merge(Map.new(overrides, fn {k, v} -> {to_string(k), v} end))
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
    |> URI.encode_query()
  end

  @doc "Sort indicator (↑ / ↓) for the active sort column; empty otherwise."
  def sort_arrow(current_sort, current_dir, column) do
    cond do
      to_string(current_sort) != to_string(column) -> ""
      to_string(current_dir) == "asc" -> " ↑"
      true -> " ↓"
    end
  end

  @doc "Direction to toggle to when the user clicks this column's header."
  def next_dir(current_sort, current_dir, column) do
    if to_string(current_sort) == to_string(column) do
      if to_string(current_dir) == "asc", do: "desc", else: "asc"
    else
      case to_string(column) do
        "eligibility" -> "desc"
        _ -> "asc"
      end
    end
  end
end
