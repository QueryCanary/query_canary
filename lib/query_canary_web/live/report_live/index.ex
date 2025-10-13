defmodule QueryCanaryWeb.ReportLive.Index do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Reports

  on_mount {QueryCanaryWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reports")
     |> assign_reports()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    report = Reports.get_report!(socket.assigns.current_scope, id)

    case Reports.delete_report(socket.assigns.current_scope, report) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report removed")
         |> assign_reports()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to delete report")}
    end
  end

  defp assign_reports(socket) do
    reports = Reports.list_reports(socket.assigns.current_scope)
    assign(socket, :reports, reports)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Reports
        <:subtitle>Create dashboards by bundling metrics into configurable groups.</:subtitle>
        <:actions>
          <.link navigate={~p"/reports/new"} class="btn btn-primary">New Report</.link>
        </:actions>
      </.header>

      <div :if={Enum.empty?(@reports)} class="card bg-base-200">
        <div class="card-body">
          <p class="text-sm text-base-content/70">
            No reports yet. Create a report to assemble metrics into a dashboard layout.
          </p>
        </div>
      </div>

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <div :for={report <- @reports} class="card bg-base-200">
          <div class="card-body space-y-2">
            <div class="flex items-start justify-between">
              <div>
                <h3 class="card-title text-lg">
                  <.link navigate={~p"/reports/#{report.id}"} class="link link-hover">
                    {report.name}
                  </.link>
                </h3>
                <p :if={report.description} class="text-sm text-base-content/70">
                  {report.description}
                </p>
              </div>
              <div class="text-xs uppercase badge badge-ghost">
                {report_owner(report)}
              </div>
            </div>
            <div class="flex flex-wrap gap-2 text-xs text-base-content/70">
              <span class="badge badge-outline">Default Range: {report.default_range}</span>
              <span class="badge badge-outline">Timezone: {report.timezone}</span>
              <span class="badge badge-outline">
                Groups: {length(report.groups || [])}
              </span>
            </div>
            <div class="flex gap-2 pt-2">
              <.link navigate={~p"/reports/#{report.id}"} class="btn btn-sm btn-primary">
                Open
              </.link>
              <.link navigate={~p"/reports/#{report.id}/edit"} class="btn btn-sm btn-ghost">
                Edit Details
              </.link>
              <.button
                phx-click="delete"
                phx-value-id={report.id}
                data-confirm="Delete this report? This cannot be undone."
                class="btn btn-sm btn-error btn-ghost ml-auto"
              >
                Delete
              </.button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp report_owner(%{team: %{name: name}}), do: "Team • #{name}"
  defp report_owner(%{user: %{email: email}}), do: "User • #{email}"
  defp report_owner(_), do: "Personal"
end
