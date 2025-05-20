defmodule QueryCanaryWeb.CheckLive.Index do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Database Checks
        <:subtitle>
          Monitor your database health and performance with scheduled SQL checks
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/checks/new"}>
            <.icon name="hero-plus" /> New Check
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Total Checks</div>
          <div class="stat-value">{@total_checks}</div>
          <div class="stat-desc">Monitoring your data quality</div>
        </div>
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Success Rate</div>
          <div class={["stat-value", if(@overall_success_rate == 100, do: "text-success")]}>
            {@overall_success_rate}%
          </div>
          <div class="stat-desc">Last 24 hours</div>
        </div>
        <div class="stat bg-base-100 shadow rounded-box">
          <div class="stat-title">Alerts</div>
          <div class={["stat-value", if(@alert_count > 0, do: "text-warning")]}>{@alert_count}</div>
          <div class="stat-desc">Requiring attention</div>
        </div>
      </div>

      <.table
        id="checks"
        rows={@streams.checks}
        row_click={fn {_id, check} -> JS.navigate(~p"/checks/#{check}") end}
      >
        <:col :let={{_id, check}} label="Name">
          <div class="">
            <div class="badge badge-soft badge-info">
              <.icon name="hero-circle-stack" /> {check.server.name}
            </div>
            <span class="font-semibold">{check.name || "Unnamed Check"}</span>
          </div>
          <div class="text-sm opacity-60 truncate max-w-xs font-mono">{check.query}</div>
        </:col>
        <:col :let={{_id, check}} label="Status">
          <%= if check.last_result do %>
            <%= if check.last_result.success do %>
              <span class="badge badge-success">Success</span>
            <% else %>
              <span class="badge badge-error">Failed</span>
            <% end %>
            <div class="text-xs opacity-70">
              {format_time_ago(check.last_run_at)}
            </div>
          <% else %>
            <span class="badge badge-outline">Pending</span>
          <% end %>
        </:col>
        <:col :let={{_id, check}} label="Alert Status">
          <%= if check.last_result && check.last_result.is_alert do %>
            <span class={alert_class(check.last_result.alert_type)}>
              {String.capitalize(to_string(check.last_result.alert_type))}
            </span>
          <% else %>
            <span class="badge badge-ghost">None</span>
          <% end %>
        </:col>
        <:action :let={{_id, check}}>
          <div class="dropdown dropdown-end">
            <label tabindex="0" class="btn btn-ghost btn-xs">
              <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
            </label>
            <ul
              tabindex="0"
              class="dropdown-content z-10 menu p-2 shadow bg-base-100 rounded-box w-52"
            >
              <li><.link navigate={~p"/checks/#{check}"}>View Details</.link></li>
              <li><.link navigate={~p"/checks/#{check}/edit"}>Edit</.link></li>
              <li>
                <a
                  class="text-error"
                  phx-click={JS.push("delete", value: %{id: check.id})}
                  data-confirm="Are you sure?"
                >
                  Delete
                </a>
              </li>
            </ul>
          </div>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Checks.subscribe_checks(socket.assigns.current_scope)
    end

    checks = Checks.list_checks_with_status(socket.assigns.current_scope)

    # Calculate overall success rate and alert count
    {success_rate, alert_count} = calculate_dashboard_metrics(checks)

    {:ok,
     socket
     |> assign(:page_title, "Database Checks")
     |> assign(:view_mode, :table)
     |> assign(:overall_success_rate, success_rate)
     |> assign(:alert_count, alert_count)
     |> assign(:total_checks, length(checks))
     |> stream(:checks, checks)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    check = Checks.get_check!(socket.assigns.current_scope, id)
    {:ok, _} = Checks.delete_check(socket.assigns.current_scope, check)

    {:noreply, stream_delete(socket, :checks, check)}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_atom(mode))}
  end

  # Helper functions
  defp format_time_ago(nil), do: "Never"

  defp format_time_ago(datetime) do
    seconds_diff = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      seconds_diff < 60 -> "Ran just now"
      seconds_diff < 3600 -> "Ran #{div(seconds_diff, 60)}m ago"
      seconds_diff < 86400 -> "Ran #{div(seconds_diff, 3600)}h ago"
      true -> "Ran #{div(seconds_diff, 86400)}d ago"
    end
  end

  defp alert_class(:failure), do: "badge badge-error"
  defp alert_class(:anomaly), do: "badge badge-warning"
  defp alert_class(:diff), do: "badge badge-warning"
  defp alert_class(_), do: "badge badge-ghost"

  defp calculate_dashboard_metrics(checks) do
    # Calculate success rate
    recent_results =
      Enum.flat_map(checks, fn check ->
        check.recent_results || []
      end)

    success_rate =
      if length(recent_results) > 0 do
        success_count = Enum.count(recent_results, & &1.success)
        trunc(success_count / length(recent_results) * 100)
      else
        # Default to 100% if no results
        100
      end

    # Count alerts
    alert_count =
      Enum.count(checks, fn check ->
        # check.alert_status && check.alert_status != "none"
        check.last_result && check.last_result.is_alert
      end)

    {success_rate, alert_count}
  end
end
