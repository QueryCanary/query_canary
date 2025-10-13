defmodule QueryCanaryWeb.ReportLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics
  alias QueryCanary.Reports
  alias QueryCanary.Reports.{Report, ReportGroup, ReportGroupMetric}
  alias Decimal

  on_mount {QueryCanaryWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    metrics = Metrics.list_metrics_for_scope(socket.assigns.current_scope, preload: [:server])
    report = Reports.get_report!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:metrics, metrics)
     |> assign(:metrics_by_id, Map.new(metrics, &{&1.id, &1}))
     |> assign_report(report)
     |> reset_new_group_form()}
  end

  @impl true
  def handle_event("add_group", %{"group" => params}, socket) do
    params = Map.take(params, ["name"])

    case Reports.create_group(socket.assigns.current_scope, socket.assigns.report, params) do
      {:ok, _group} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group added")
         |> refresh_report()
         |> reset_new_group_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :group_error, changeset.errors |> Keyword.values() |> Enum.join(", "))}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    group = find_group(socket.assigns.report, id)

    with %ReportGroup{} = group <- group,
         {:ok, _} <- Reports.delete_group(socket.assigns.current_scope, group) do
      {:noreply,
       socket
       |> put_flash(:info, "Group removed")
       |> refresh_report()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unable to remove group")}
    end
  end

  def handle_event("rename_group", %{"group" => %{"id" => id, "name" => name}}, socket) do
    case find_group(socket.assigns.report, id) do
      %ReportGroup{} = group ->
        case Reports.update_group(socket.assigns.current_scope, group, %{name: name}) do
          {:ok, _} ->
            {:noreply, refresh_report(socket)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :group_error, changeset)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "add_metric",
        %{"add_metric" => %{"group_id" => group_id, "metric_id" => metric_id}},
        socket
      ) do
    with %ReportGroup{} = group <- find_group(socket.assigns.report, group_id),
         {metric_id_int, ""} <- Integer.parse(metric_id),
         {:ok, metric} <- metric_from_socket(socket, metric_id_int),
         {:ok, _gm} <-
           Reports.add_metric_to_group(socket.assigns.current_scope, group, metric) do
      {:noreply,
       socket
       |> put_flash(:info, "Metric added")
       |> refresh_report()}
    else
      :not_found ->
        {:noreply, put_flash(socket, :error, "Metric not available")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to add metric")}
    end
  end

  def handle_event(
        "update_metric",
        %{"metric_config" => %{"id" => id, "display_name" => display_name}},
        socket
      ) do
    case find_group_metric(socket.assigns.report, id) do
      %ReportGroupMetric{} = gm ->
        settings =
          gm.settings
          |> Map.put("display_name", display_name)

        case Reports.update_group_metric(socket.assigns.current_scope, gm, %{settings: settings}) do
          {:ok, _} ->
            {:noreply, refresh_report(socket)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :metric_error, changeset)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_metric", %{"id" => id}, socket) do
    case find_group_metric(socket.assigns.report, id) do
      %ReportGroupMetric{} = gm ->
        case Reports.remove_metric_from_group(socket.assigns.current_scope, gm) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Metric removed")
             |> refresh_report()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Unable to remove metric")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp refresh_report(socket) do
    report = Reports.get_report!(socket.assigns.current_scope, socket.assigns.report.id)
    assign_report(socket, report)
  end

  defp assign_report(socket, %Report{} = report) do
    metric_results = Reports.metric_results_for_report(report, limit: 90)

    assign(socket,
      report: report,
      metric_results: metric_results
    )
  end

  defp metric_from_socket(socket, id) do
    case Map.fetch(socket.assigns.metrics_by_id, id) do
      {:ok, metric} -> {:ok, metric}
      :error -> :not_found
    end
  end

  defp find_group(%Report{} = report, id) do
    with {int_id, ""} <- Integer.parse("#{id}") do
      Enum.find(report.groups, &(&1.id == int_id))
    else
      _ -> nil
    end
  end

  defp find_group_metric(%Report{} = report, id) do
    with {int_id, ""} <- Integer.parse("#{id}") do
      report.groups
      |> Enum.flat_map(& &1.group_metrics)
      |> Enum.find(&(&1.id == int_id))
    else
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@report.name}
        <:subtitle>
          Default Range: {@report.default_range} • Timezone: {@report.timezone}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/reports"} class="btn btn-ghost">
            <.icon name="hero-arrow-left" /> Back
          </.link>
          <.link navigate={~p"/reports/#{@report.id}/edit"} class="btn btn-primary">
            Edit Details
          </.link>
        </:actions>
      </.header>

      <section class="grid gap-4">
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">Add Group</h3>
            <.form for={@new_group_form} phx-submit="add_group" class="flex gap-2">
              <.input field={@new_group_form[:name]} placeholder="Group name" required class="flex-1" />
              <.button type="submit" variant="primary">Add</.button>
            </.form>
          </div>
        </div>

        <div :for={group <- @report.groups} class="card bg-base-200">
          <div class="card-body space-y-4">
            <div class="flex items-center gap-2">
              <.form
                for={%{}}
                as={:group}
                phx-change="rename_group"
                phx-value-id={group.id}
                class="flex flex-1 items-center gap-2"
              >
                <input type="hidden" name="group[id]" value={group.id} />
                <.input
                  name="group[name]"
                  value={group.name}
                  phx-debounce="blur"
                  label="Group Name"
                  class="flex-1"
                />
              </.form>
              <.button
                class="btn btn-ghost btn-sm text-error"
                phx-click="delete_group"
                phx-value-id={group.id}
                data-confirm="Remove this group?"
              >
                Remove Group
              </.button>
            </div>

            <div class="bg-base-300 rounded-lg p-4 space-y-3">
              <h4 class="font-semibold text-sm uppercase tracking-wide">Add metric</h4>
              <.form
                for={%{}}
                as={:add_metric}
                phx-submit="add_metric"
                class="flex gap-2 items-center"
              >
                <input type="hidden" name="add_metric[group_id]" value={group.id} />
                <select name="add_metric[metric_id]" class="select select-bordered flex-1" required>
                  <option value="">Select metric…</option>
                  <%= for metric <- available_metrics_for_group(group, @metrics_by_id) do %>
                    <option value={metric.id}>
                      {metric.name} — {(metric.server && metric.server.name) ||
                        "Server ##{metric.server_id}"}
                    </option>
                  <% end %>
                </select>
                <.button type="submit" class="btn btn-primary btn-sm">
                  Add Metric
                </.button>
              </.form>

              <div :if={Enum.empty?(group.group_metrics)} class="text-sm text-base-content/70">
                No metrics in this group yet.
              </div>

              <div :for={group_metric <- group.group_metrics} class="grid gap-3">
                <div class="card bg-base-100">
                  <div class="card-body space-y-2">
                    <div class="flex justify-between items-center">
                      <div>
                        <h4 class="font-semibold text-base">
                          {group_metric.settings["display_name"] ||
                            group_metric.metric.name}
                        </h4>
                        <p class="text-xs text-base-content/70">
                          Source Metric: {group_metric.metric.name} • Server: {server_label(
                            group_metric.metric
                          )}
                        </p>
                      </div>
                      <.button
                        class="btn btn-sm btn-ghost text-error"
                        phx-click="remove_metric"
                        phx-value-id={group_metric.id}
                      >
                        Remove
                      </.button>
                    </div>

                    <% results = Map.get(@metric_results, group_metric.metric_id, []) %>
                    <% latest = List.last(results) %>
                    <div class="grid grid-cols-2 gap-4 text-sm">
                      <div>
                        <div class="text-xs uppercase text-base-content/60">Latest Value</div>
                        <div class="text-lg font-semibold">
                          {(latest && format_value(latest.value)) || "—"}
                        </div>
                      </div>
                      <div>
                        <div class="text-xs uppercase text-base-content/60">Updated</div>
                        <div class="text-lg font-semibold">
                          {(latest && format_timestamp(latest.to_ts, @report.timezone)) || "—"}
                        </div>
                      </div>
                    </div>

                    <.form
                      for={%{}}
                      as={:metric_config}
                      phx-change="update_metric"
                      class="grid gap-2 md:grid-cols-2"
                    >
                      <input type="hidden" name="metric_config[id]" value={group_metric.id} />
                      <.input
                        name="metric_config[display_name]"
                        label="Display Name"
                        value={group_metric.settings["display_name"] || group_metric.metric.name}
                        phx-debounce="blur"
                      />
                      <.input
                        name="metric_config[note]"
                        label="Notes (coming soon)"
                        value=""
                        disabled
                      />
                    </.form>

                    <div class="overflow-x-auto">
                      <table class="table table-zebra text-sm">
                        <thead>
                          <tr>
                            <th>From</th>
                            <th>To</th>
                            <th class="text-right">Value</th>
                          </tr>
                        </thead>
                        <tbody>
                          <%= for res <- recent_results(results, 8) do %>
                            <tr>
                              <td>{format_timestamp(res.from_ts, @report.timezone)}</td>
                              <td>{format_timestamp(res.to_ts, @report.timezone)}</td>
                              <td class="text-right">{format_value(res.value)}</td>
                            </tr>
                          <% end %>
                          <tr :if={Enum.empty?(results)}>
                            <td colspan="3" class="text-center text-base-content/60">
                              No metric runs captured in this window.
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp available_metrics_for_group(group, metrics_by_id) do
    used_ids = Enum.map(group.group_metrics, & &1.metric_id) |> MapSet.new()

    metrics_by_id
    |> Map.values()
    |> Enum.reject(&MapSet.member?(used_ids, &1.id))
    |> Enum.sort_by(& &1.name)
  end

  defp server_label(%{server: %{name: name}}), do: name
  defp server_label(%{server: nil, server_id: id}), do: "Server ##{id}"

  defp reset_new_group_form(socket) do
    assign(socket, :new_group_form, to_form(%{"name" => ""}, as: :group))
  end

  defp format_value(nil), do: "—"

  defp format_value(%Decimal{} = dec) do
    dec
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp format_value(value) when is_integer(value), do: Integer.to_string(value)

  defp format_value(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp format_value(value), do: to_string(value)

  defp format_timestamp(nil, _tz), do: "—"

  defp format_timestamp(%DateTime{} = utc, tz) do
    tz = tz || "Etc/UTC"

    utc
    |> DateTime.shift_zone!(tz)
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp recent_results(results, count) do
    results
    |> Enum.reverse()
    |> Enum.take(count)
    |> Enum.reverse()
  end
end
