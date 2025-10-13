defmodule QueryCanaryWeb.ReportLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Accounts
  alias QueryCanary.Reports
  alias QueryCanary.Reports.Report

  on_mount {QueryCanaryWeb.UserAuth, :require_authenticated}

  @default_ranges [
    {"Today", "today"},
    {"Yesterday", "yesterday"},
    {"Last 7 days", "7d"},
    {"Last 30 days", "30d"},
    {"Last quarter", "quarter"},
    {"Custom", "custom"}
  ]

  @impl true
  def mount(params, _session, socket) do
    teams = Accounts.list_teams(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:teams, teams)
     |> assign(:default_ranges, @default_ranges)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    changeset =
      Reports.change_report(socket.assigns.current_scope, %Report{
        timezone: "Etc/UTC",
        default_range: "today"
      })

    socket
    |> assign(:page_title, "New Report")
    |> assign(:report, %Report{})
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    report = Reports.get_report!(socket.assigns.current_scope, id)
    changeset = Reports.change_report(socket.assigns.current_scope, report)

    socket
    |> assign(:page_title, "Edit Report")
    |> assign(:report, report)
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>
          Reports collect metrics into grouped dashboards. Define ownership and default time window here.
        </:subtitle>
      </.header>

      <.form for={@form} id="report-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="3" />
        <.input
          field={@form[:default_range]}
          type="select"
          label="Default Date Range"
          options={@default_ranges}
        />
        <.input field={@form[:timezone]} type="text" label="Timezone (IANA name)" />

        <div class="form-control">
          <label class="label">
            <span class="label-text text-base font-semibold">Ownership</span>
          </label>
          <div class="join join-vertical lg:join-horizontal w-full">
            <label class="join-item btn btn-outline">
              <input
                type="radio"
                name="report[ownership]"
                value="personal"
                checked={personal_owner?(@form)}
                class="hidden"
              /> Personal
            </label>
            <label
              :for={team <- @teams}
              class="join-item btn btn-outline flex-1 flex items-center justify-center"
            >
              <input
                type="radio"
                name="report[ownership]"
                value={"team:#{team.id}"}
                checked={team_owner?(@form, team.id)}
                class="hidden"
              />
              {team.name}
            </label>
          </div>
          <p class="text-xs text-base-content/70 mt-2">
            Select a team to make this report visible to everyone on that team.
          </p>
        </div>

        <footer class="mt-6 flex gap-2">
          <.button variant="primary" phx-disable-with="Saving...">
            Save Report
          </.button>
          <.button navigate={cancel_path(@report)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"report" => report_params}, socket) do
    params = normalize_owner(report_params)

    changeset =
      Reports.change_report(socket.assigns.current_scope, socket.assigns.report, params)

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"report" => report_params}, socket) do
    params = normalize_owner(report_params)

    save_report(socket, socket.assigns.live_action, params)
  end

  defp save_report(socket, :new, params) do
    case Reports.create_report(socket.assigns.current_scope, params) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report created")
         |> push_navigate(to: ~p"/reports/#{report.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_report(socket, :edit, params) do
    case Reports.update_report(socket.assigns.current_scope, socket.assigns.report, params) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report updated")
         |> push_navigate(to: ~p"/reports/#{report.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp personal_owner?(form) do
    case form.source.data do
      %Report{team_id: nil} -> true
      %Report{} -> false
      %{"team_id" => team_id} -> is_nil(team_id) or team_id in ["", nil]
      _ -> false
    end
  end

  defp team_owner?(form, team_id) do
    case form.source.data do
      %Report{team_id: ^team_id} -> true
      %Report{} -> false
      %{"team_id" => id} -> "#{team_id}" == "#{id}"
      _ -> false
    end
  end

  defp normalize_owner(params) do
    case Map.get(params, "ownership") do
      "personal" ->
        params
        |> Map.put("team_id", nil)
        |> Map.delete("ownership")

      "team:" <> team_id ->
        params
        |> Map.put("team_id", team_id)
        |> Map.delete("ownership")

      _ ->
        params
    end
  end

  defp cancel_path(%Report{id: nil}), do: ~p"/reports"
  defp cancel_path(%Report{id: id}), do: ~p"/reports/#{id}"
end
