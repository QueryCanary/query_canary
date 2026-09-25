defmodule QueryCanaryWeb.CheckLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks
  alias QueryCanary.Checks.Check
  alias QueryCanaryWeb.NotificationComponents
  alias QueryCanaryWeb.ScheduleForm
  import QueryCanaryWeb.NotificationComponents, only: [notification_fields: 1]
  import QueryCanaryWeb.Components.SchedulePicker, only: [schedule_picker: 1]

  on_mount {QueryCanaryWeb.CheckAuth, :edit}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage check records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="check-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
        <.input field={@form[:public]} type="checkbox" label="Publicly Viewable?" />
        <.schedule_picker
          form={@form}
          ui={@schedule_ui}
          next_runs={@next_runs}
          auto_timezone={@auto_timezone}
        />
        <.live_component
          module={QueryCanaryWeb.Components.SQLEditor}
          id="check-sql-editor"
          server={@check.server}
          input_name={@form[:query].name}
          value={@form[:query].value}
        />
        <.notification_fields
          form={@form}
          settings={@notification_settings}
          team_id={@check.server.team_id}
          email_destination={
            if @check.server.team_id, do: "All active team members", else: @current_scope.user.email
          }
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Check</.button>
          <.button navigate={return_path(@current_scope, @return_to, @check)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    check = Checks.get_check!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Check")
    |> assign(:check, check)
    |> assign(:schedule_ui, ScheduleForm.initial_ui(check))
    |> assign(:next_runs, QueryCanary.Checks.Schedule.next_runs(check.schedule, check.timezone))
    |> assign(:auto_timezone, false)
    |> assign(
      :notification_settings,
      NotificationComponents.settings(
        socket.assigns.current_scope,
        check.server,
        connected?(socket)
      )
    )
    |> assign(:form, to_form(Checks.change_check(socket.assigns.current_scope, check)))
  end

  defp apply_action(socket, :new, _params) do
    check = %Check{user_id: socket.assigns.current_scope.user.id, schedule: "0 8 * * *"}

    socket
    |> assign(:page_title, "New Check")
    |> assign(:check, check)
    |> assign(:schedule_ui, ScheduleForm.initial_ui(check))
    |> assign(:next_runs, QueryCanary.Checks.Schedule.next_runs(check.schedule, check.timezone))
    |> assign(:auto_timezone, true)
    |> assign(:form, to_form(Checks.change_check(socket.assigns.current_scope, check)))
  end

  @impl true
  def handle_event("validate", %{"check" => check_params} = params, socket) do
    {check_params, ui, error} =
      ScheduleForm.prepare(
        check_params,
        params["schedule_ui"],
        socket.assigns.schedule_ui,
        socket.assigns.form[:schedule].value
      )

    changeset =
      Checks.change_check(socket.assigns.current_scope, socket.assigns.check, check_params)
      |> ScheduleForm.add_schedule_error(error)

    {:noreply,
     assign(socket,
       form: to_form(changeset, action: :validate),
       schedule_ui: ui,
       next_runs: ScheduleForm.next_runs(changeset),
       auto_timezone: false
     )}
  end

  def handle_event("save", %{"check" => check_params} = params, socket) do
    {check_params, ui, error} =
      ScheduleForm.prepare(
        check_params,
        params["schedule_ui"],
        socket.assigns.schedule_ui,
        socket.assigns.form[:schedule].value
      )

    socket = assign(socket, schedule_ui: ui, auto_timezone: false)

    if error do
      changeset =
        Checks.change_check(socket.assigns.current_scope, socket.assigns.check, check_params)
        |> ScheduleForm.add_schedule_error(error)

      {:noreply, assign(socket, form: to_form(changeset), next_runs: [])}
    else
      save_check(socket, socket.assigns.live_action, check_params)
    end
  end

  def handle_event("detect_timezone", %{"timezone" => timezone}, socket) do
    if socket.assigns.auto_timezone and
         match?({:ok, _}, DateTime.shift_zone(DateTime.utc_now(), timezone)) do
      changeset = Ecto.Changeset.put_change(socket.assigns.form.source, :timezone, timezone)

      {:noreply,
       assign(socket,
         form: to_form(changeset),
         next_runs: ScheduleForm.next_runs(changeset),
         auto_timezone: false
       )}
    else
      {:noreply, socket}
    end
  end

  defp save_check(socket, :edit, check_params) do
    case Checks.update_check(socket.assigns.current_scope, socket.assigns.check, check_params) do
      {:ok, check} ->
        {:noreply,
         socket
         |> put_flash(:info, "Check updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, check)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset), next_runs: ScheduleForm.next_runs(changeset))}
    end
  end

  defp save_check(socket, :new, check_params) do
    case Checks.create_check(socket.assigns.current_scope, check_params) do
      {:ok, check} ->
        {:noreply,
         socket
         |> put_flash(:info, "Check created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, check)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset), next_runs: ScheduleForm.next_runs(changeset))}
    end
  end

  defp return_path(_scope, "index", _check), do: ~p"/checks"
  defp return_path(_scope, "show", check), do: ~p"/checks/#{check}"
end
