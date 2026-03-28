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
     |> assign(:editing_group_id, nil)
     |> assign(:editing_metric_id, nil)
     |> assign(:adding_metric_group_id, nil)
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
         |> assign(:adding_metric_group_id, nil)
         |> refresh_report()
         |> reset_new_group_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :group_error, changeset.errors |> Keyword.values() |> Enum.join(", "))}
    end
  end

  def handle_event("start_group_edit", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_group_id, parse_int(id))
     |> assign(:editing_metric_id, nil)
     |> assign(:adding_metric_group_id, nil)}
  end

  def handle_event("cancel_group_edit", _params, socket) do
    {:noreply, assign(socket, :editing_group_id, nil)}
  end

  def handle_event("save_group", %{"group" => %{"id" => id, "name" => name}}, socket) do
    case find_group(socket.assigns.report, id) do
      %ReportGroup{} = group ->
        case Reports.update_group(socket.assigns.current_scope, group, %{name: name}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Group updated")
             |> assign(:editing_group_id, nil)
             |> refresh_report()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :group_error, changeset)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_add_metric", %{"id" => id}, socket) do
    group_id = parse_int(id)

    new_value =
      if socket.assigns.adding_metric_group_id == group_id do
        nil
      else
        group_id
      end

    {:noreply, assign(socket, :adding_metric_group_id, new_value)}
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    case find_group(socket.assigns.report, id) do
      %ReportGroup{} = group ->
        case Reports.delete_group(socket.assigns.current_scope, group) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Group removed")
             |> assign(:editing_group_id, nil)
             |> assign(:adding_metric_group_id, nil)
             |> refresh_report()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Unable to remove group")}
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
       |> assign(:editing_metric_id, nil)
       |> assign(:adding_metric_group_id, nil)
       |> refresh_report()}
    else
      :not_found ->
        {:noreply, put_flash(socket, :error, "Metric not available")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to add metric")}
    end
  end

  def handle_event("start_metric_edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_metric_id, parse_int(id))}
  end

  def handle_event("cancel_metric_edit", _params, socket) do
    {:noreply, assign(socket, :editing_metric_id, nil)}
  end

  def handle_event(
        "save_metric",
        %{"metric_config" => %{"id" => id, "display_name" => display_name}},
        socket
      ) do
    case find_group_metric(socket.assigns.report, id) do
      %ReportGroupMetric{} = gm ->
        case Reports.update_group_metric(socket.assigns.current_scope, gm, %{
               settings: Map.put(gm.settings, "display_name", display_name)
             }) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Metric updated")
             |> assign(:editing_metric_id, nil)
             |> refresh_report()}

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
             |> assign(:editing_metric_id, nil)
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
    table_state = build_table_state(report, metric_results, socket.assigns.metrics_by_id)

    assign(socket,
      report: report,
      metric_results: metric_results,
      table_days: table_state.days,
      table_groups: table_state.groups,
      table_rows: table_state.rows
    )
  end

  defp metric_from_socket(socket, id) do
    case Map.fetch(socket.assigns.metrics_by_id, id) do
      {:ok, metric} -> {:ok, metric}
      :error -> :not_found
    end
  end

  defp find_group(%Report{} = report, id) do
    parsed = parse_int(id)
    Enum.find(report.groups, &(&1.id == parsed))
  end

  defp find_group_metric(%Report{} = report, id) do
    parsed = parse_int(id)

    report.groups
    |> Enum.flat_map(& &1.group_metrics)
    |> Enum.find(&(&1.id == parsed))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.fluid_app flash={@flash} current_scope={@current_scope}>
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

      <section class="space-y-6">
        <div class="space-y-3">
          <div class="flex flex-col gap-2 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h2 class="text-lg font-semibold tracking-tight">Report Overview</h2>
              <div class="text-xs text-base-content/60">
                Showing {length(@table_days)} day(s) ending {format_day(List.last(@table_days))}
              </div>
            </div>

            <.form
              for={@new_group_form}
              phx-submit="add_group"
              class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3"
            >
              <.input
                field={@new_group_form[:name]}
                placeholder="New group name"
                required
                class="min-w-[12rem]"
              />
              <.button type="submit" variant="primary" class="sm:w-auto">
                Add Group
              </.button>
            </.form>
          </div>

          <div
            :if={!Enum.empty?(@table_rows)}
            class="overflow-x-auto rounded border border-base-300 bg-base-100 shadow-sm"
          >
            <table class="min-w-full border-collapse text-xs leading-tight">
              <thead class="bg-base-200 sticky top-0 z-20">
                <tr>
                  <th class="sticky left-0 z-30 bg-base-200 px-3 py-2 text-left font-medium text-base-content/70 border-b border-base-300 w-52">
                    Metric
                  </th>
                  <%= for day <- @table_days do %>
                    <th class="px-2 py-2 text-center font-medium text-base-content/70 border-b border-base-300 w-16">
                      <div class="flex flex-col items-center gap-0.5">
                        <span>{format_day_short(day)}</span>
                        <span class="text-[9px] font-normal text-base-content/50">
                          {day_of_week(day)}
                        </span>
                      </div>
                    </th>
                  <% end %>
                  <th class="px-2 py-2 text-center font-medium text-base-content/70 border-b border-base-300 w-16">
                    Δ 7d
                  </th>
                  <th class="px-2 py-2 text-center font-medium text-base-content/70 border-b border-base-300 w-16">
                    Δ Start
                  </th>
                  <th class="px-2 py-2 text-center font-medium text-base-content/70 border-b border-base-300 w-16">
                    Avg
                  </th>
                  <th class="px-3 py-2 text-left font-medium text-base-content/70 border-b border-base-300 w-48">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for group <- @table_groups do %>
                  <% group_editing? = @editing_group_id == group.id %>
                  <% adding_metric? = @adding_metric_group_id == group.id %>
                  <tr>
                    <td
                      class="sticky left-0 z-10 bg-base-200/80 backdrop-blur px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-base-content/60 border-t border-b border-base-300"
                      colspan={length(@table_days) + 5}
                    >
                      <div class="flex flex-col gap-2 lg:flex-row lg:items-center lg:justify-between">
                        <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-2">
                          <%= if group_editing? do %>
                            <.form
                              for={%{}}
                              as={:group}
                              phx-submit="save_group"
                              class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-2"
                            >
                              <input type="hidden" name="group[id]" value={group.id} />
                              <input
                                type="text"
                                name="group[name]"
                                value={group.name}
                                class="input input-sm w-full sm:w-64"
                                autofocus
                              />
                              <div class="flex gap-2">
                                <button type="submit" class="btn btn-xs btn-primary sm:btn-sm">
                                  Save
                                </button>
                                <button
                                  type="button"
                                  class="btn btn-xs btn-ghost sm:btn-sm"
                                  phx-click="cancel_group_edit"
                                >
                                  Cancel
                                </button>
                              </div>
                            </.form>
                          <% else %>
                            <div class="flex items-center gap-2">
                              <span class="text-sm font-semibold tracking-wide">{group.name}</span>
                              <button
                                type="button"
                                class="btn btn-ghost btn-xs"
                                phx-click="start_group_edit"
                                phx-value-id={group.id}
                              >
                                <.icon name="hero-pencil-square" class="h-4 w-4" />
                              </button>
                              <button
                                class="btn btn-ghost btn-xs text-error"
                                phx-click="delete_group"
                                phx-value-id={group.id}
                                data-confirm="Remove this group?"
                              >
                                <.icon name="hero-trash" class="h-4 w-4" />
                              </button>
                            </div>
                          <% end %>
                        </div>

                        <div class="flex flex-wrap items-center gap-2">
                          <%= if adding_metric? do %>
                            <form phx-submit="add_metric" class="flex flex-wrap gap-2 items-center">
                              <input type="hidden" name="add_metric[group_id]" value={group.id} />
                              <select
                                name="add_metric[metric_id]"
                                class="select select-bordered select-xs sm:select-sm min-w-[10rem]"
                                required
                              >
                                <option value="">Select metric…</option>
                                <%= for metric <-
                                      available_metrics_for_group(@report, group.id, @metrics_by_id) do %>
                                  <option value={metric.id}>
                                    {metric.name} — {(metric.server && metric.server.name) ||
                                      "Server ##{metric.server_id}"}
                                  </option>
                                <% end %>
                              </select>
                              <button type="submit" class="btn btn-xs btn-primary sm:btn-sm">
                                Add
                              </button>
                              <button
                                type="button"
                                class="btn btn-xs btn-ghost sm:btn-sm"
                                phx-click="toggle_add_metric"
                                phx-value-id={group.id}
                              >
                                Cancel
                              </button>
                            </form>
                          <% else %>
                            <button
                              type="button"
                              class="btn btn-ghost btn-xs"
                              phx-click="toggle_add_metric"
                              phx-value-id={group.id}
                            >
                              <.icon name="hero-plus" class="h-4 w-4" />
                              <span class="sr-only">Add metric</span>
                            </button>
                          <% end %>
                        </div>
                      </div>
                    </td>
                  </tr>

                  <% rows = Enum.filter(@table_rows, &(&1.group_id == group.id)) %>

                  <%= if Enum.empty?(rows) do %>
                    <tr>
                      <td
                        class="sticky left-0 z-10 bg-base-100 px-3 py-2 text-sm text-base-content/60 border-b border-base-200"
                        colspan={length(@table_days) + 5}
                      >
                        No metrics in this group yet.
                      </td>
                    </tr>
                  <% else %>
                    <%= for row <- rows do %>
                      <% metric_editing? = @editing_metric_id == row.group_metric_id %>
                      <tr class="hover:bg-base-200/30">
                        <td class="sticky left-0 z-10 bg-base-100 px-3 py-1.5 font-medium text-base-content border-b border-base-200">
                          <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-2">
                            <%= if metric_editing? do %>
                              <.form
                                for={%{}}
                                as={:metric_config}
                                phx-submit="save_metric"
                                class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-2"
                              >
                                <input
                                  type="hidden"
                                  name="metric_config[id]"
                                  value={row.group_metric_id}
                                />
                                <input
                                  type="text"
                                  name="metric_config[display_name]"
                                  value={row.display_name}
                                  class="input input-xs w-full sm:w-40"
                                  autofocus
                                />
                                <div class="flex gap-2">
                                  <button class="btn btn-xs btn-primary" type="submit">
                                    Save
                                  </button>
                                  <button
                                    class="btn btn-xs btn-ghost"
                                    type="button"
                                    phx-click="cancel_metric_edit"
                                  >
                                    Cancel
                                  </button>
                                </div>
                              </.form>
                            <% else %>
                              <div class="flex items-center gap-2">
                                <span class="truncate">{row.display_name}</span>
                                <button
                                  type="button"
                                  class="btn btn-ghost btn-xs"
                                  phx-click="start_metric_edit"
                                  phx-value-id={row.group_metric_id}
                                >
                                  <.icon name="hero-pencil-square" class="h-4 w-4" />
                                </button>
                                <button
                                  class="btn btn-ghost btn-xs text-error"
                                  phx-click="remove_metric"
                                  phx-value-id={row.group_metric_id}
                                  data-confirm="Remove this metric from the report?"
                                >
                                  <.icon name="hero-trash" class="h-4 w-4" />
                                </button>
                              </div>
                            <% end %>
                          </div>
                        </td>

                        <%= for day <- @table_days do %>
                          <% value = Map.get(row.values, day) %>
                          <% cls = heat_class(value, row.min, row.max) %>
                          <td
                            class={"relative px-1.5 py-1 text-center align-middle border-b border-base-200 #{cls}"}
                            title={"#{row.display_name} #{format_day(day)}: #{fmt(value, row.opts)}"}
                          >
                            <div class="font-medium tabular-nums">
                              {fmt_compact(value, row.opts)}
                            </div>
                            <div class="absolute inset-0 pointer-events-none">
                              <div class={"h-full w-full opacity-15 " <> heat_bg_color(value, row.min, row.max)}>
                              </div>
                            </div>
                          </td>
                        <% end %>

                        <td class="px-2 py-1 text-center border-b border-base-200">
                          <.delta_chip latest={row.latest} past={row.week_ago} />
                        </td>
                        <td class="px-2 py-1 text-center border-b border-base-200">
                          <.delta_chip latest={row.latest} past={row.fortnight} />
                        </td>
                        <td class="px-2 py-1 text-center border-b border-base-200 text-base-content/70 tabular-nums">
                          {fmt(row.avg, row.opts)}
                        </td>
                        <td class="px-3 py-1 text-left border-b border-base-200">
                          <div class="flex flex-wrap gap-2 text-xs text-base-content/60">
                            <span>
                              Latest: {fmt(row.latest, row.opts)}
                            </span>
                            <span>
                              Avg: {fmt(row.avg, row.opts)}
                            </span>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>

          <div :if={Enum.empty?(@table_rows)} class="alert alert-info text-sm">
            No metric data available yet. Add metrics to this report to see trends here.
          </div>

          <div class="flex items-center gap-4 pt-1 text-[10px] text-base-content/60">
            <div class="flex items-center gap-1">
              <span class="inline-block h-3 w-5 rounded bg-emerald-200"></span> High
            </div>
            <div class="flex items-center gap-1">
              <span class="inline-block h-3 w-5 rounded border border-base-300 bg-base-100"></span>
              Mid
            </div>
            <div class="flex items-center gap-1">
              <span class="inline-block h-3 w-5 rounded bg-rose-200"></span> Low
            </div>
          </div>
        </div>
      </section>
    </Layouts.fluid_app>
    """
  end

  defp reset_new_group_form(socket) do
    assign(socket, :new_group_form, to_form(%{"name" => ""}, as: :group))
  end

  defp build_table_state(report, metric_results, metrics_by_id) do
    tz = report.timezone || "Etc/UTC"
    max_days = range_to_days(report.default_range || "30d")

    result_days =
      metric_results
      |> Enum.flat_map(fn {_metric_id, results} ->
        Enum.map(results, fn res ->
          res.from_ts
          |> DateTime.shift_zone!(tz)
          |> DateTime.to_date()
        end)
      end)
      |> Enum.uniq()

    base_days = default_days(report, max_days)

    days =
      (base_days ++ Enum.reject(result_days, &(&1 in base_days)))
      |> Enum.uniq()
      |> Enum.sort(Date)
      |> maybe_truncate(max_days)

    groups =
      Enum.map(report.groups, fn group ->
        %{id: group.id, name: group.name}
      end)

    rows =
      for group <- report.groups,
          group_metric <- group.group_metrics do
        metric_id = group_metric.metric_id
        metric = Map.get(metrics_by_id, metric_id, group_metric.metric)
        results = Map.get(metric_results, metric_id, [])

        value_map =
          results
          |> Enum.map(fn res ->
            day =
              res.from_ts
              |> DateTime.shift_zone!(tz)
              |> DateTime.to_date()

            {day, numeric_value(res.value)}
          end)
          |> Enum.into(%{})

        values_for_days =
          Enum.reduce(days, %{}, fn day, acc ->
            Map.put(acc, day, Map.get(value_map, day))
          end)

        numbers =
          values_for_days
          |> Map.values()
          |> Enum.filter(&is_number/1)

        stats = value_stats(numbers)

        %{
          group_id: group.id,
          group_name: group.name,
          group_metric_id: group_metric.id,
          metric_id: metric_id,
          display_name:
            group_metric.settings["display_name"] ||
              (metric && metric.name) ||
              "Metric #{metric_id}",
          values: values_for_days,
          min: stats.min,
          max: stats.max,
          avg: stats.avg,
          latest: value_at_offset(values_for_days, days, 0),
          week_ago: value_at_offset(values_for_days, days, 7),
          fortnight: value_at_offset(values_for_days, days, length(days) - 1),
          opts: Map.get(group_metric.settings, "display", %{})
        }
      end

    %{days: days, groups: groups, rows: rows}
  end

  defp maybe_truncate(days, max_days) do
    length = length(days)

    if length > max_days do
      Enum.slice(days, length - max_days, max_days)
    else
      days
    end
  end

  defp default_days(report, max_days) do
    today = Date.utc_today()

    end_day =
      case report.default_range do
        "yesterday" -> Date.add(today, -1)
        _ -> today
      end

    0..(max_days - 1)
    |> Enum.map(&Date.add(end_day, -&1))
    |> Enum.sort(Date)
  end

  defp range_to_days(range) do
    case range do
      "today" -> 1
      "yesterday" -> 1
      "7d" -> 7
      "30d" -> 30
      "quarter" -> 90
      _ -> 30
    end
  end

  defp value_stats([]), do: %{min: nil, max: nil, avg: nil}

  defp value_stats(values) do
    min = Enum.min(values)
    max = Enum.max(values)
    avg = Enum.sum(values) / max(length(values), 1)
    %{min: min, max: max, avg: avg}
  end

  defp numeric_value(nil), do: nil
  defp numeric_value(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp numeric_value(value) when is_integer(value), do: value * 1.0
  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(_), do: nil

  defp value_at_offset(_values, [], _offset), do: nil

  defp value_at_offset(values, days, offset) do
    case day_at_offset(days, offset) do
      nil -> nil
      day -> Map.get(values, day)
    end
  end

  defp day_at_offset(days, offset) do
    idx = length(days) - 1 - offset

    cond do
      idx < 0 -> nil
      idx >= length(days) -> nil
      true -> Enum.at(days, idx)
    end
  end

  defp available_metrics_for_group(report, group_id, metrics_by_id) do
    used_ids =
      report.groups
      |> Enum.find(&(&1.id == group_id))
      |> case do
        nil ->
          MapSet.new()

        group ->
          dbg(group)
          group.group_metrics |> Enum.map(& &1.metric_id) |> MapSet.new()
      end

    metrics_by_id
    |> Map.values()
    |> Enum.reject(&MapSet.member?(used_ids, &1.id))
    |> Enum.sort_by(& &1.name)
  end

  defp format_day(nil), do: "—"
  defp format_day(d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_day_short(d), do: Calendar.strftime(d, "%m-%d")
  defp day_of_week(d), do: Calendar.strftime(d, "%a")

  defp heat_class(nil, _min, _max), do: "text-base-content/40"
  defp heat_class(_v, nil, _max), do: "text-base-content/70"
  defp heat_class(_v, _min, nil), do: "text-base-content/70"
  defp heat_class(_v, min, max) when max == min, do: "text-base-content/70"

  defp heat_class(v, min, max) do
    ratio = (v - min) / max(1.0, max - min)

    cond do
      ratio >= 0.75 -> "text-emerald-700"
      ratio >= 0.50 -> "text-emerald-600"
      ratio >= 0.25 -> "text-base-content"
      ratio >= 0.10 -> "text-rose-600"
      true -> "text-rose-700"
    end
  end

  defp heat_bg_color(nil, _min, _max), do: "bg-base-100"
  defp heat_bg_color(_v, nil, _max), do: "bg-base-100"
  defp heat_bg_color(_v, _min, nil), do: "bg-base-100"
  defp heat_bg_color(_v, min, max) when max == min, do: "bg-base-100"

  defp heat_bg_color(v, min, max) do
    ratio = (v - min) / max(1.0, max - min)

    cond do
      ratio >= 0.75 -> "bg-emerald-300"
      ratio >= 0.50 -> "bg-emerald-200"
      ratio >= 0.25 -> "bg-base-100"
      ratio >= 0.10 -> "bg-rose-200"
      true -> "bg-rose-300"
    end
  end

  defp fmt(nil, _opts), do: "—"
  defp fmt(value, opts) when is_number(value), do: fmt_number(value, opts)
  defp fmt(_value, _opts), do: "—"

  defp fmt_compact(nil, _opts), do: "—"
  defp fmt_compact(value, opts), do: fmt_number(value, opts)

  defp fmt_number(value, opts) do
    cond do
      opts[:pct] -> "#{Float.round(value, 1)}%"
      opts[:money] -> "$" <> to_compact(value)
      true -> to_compact(value)
    end
  end

  defp to_compact(value) when is_integer(value), do: Integer.to_string(value)

  defp to_compact(value) when is_float(value) do
    abs_val = abs(value)

    cond do
      abs_val >= 1_000_000 ->
        :io_lib.format("~.1fM", [value / 1_000_000]) |> IO.iodata_to_binary()

      abs_val >= 10_000 ->
        :io_lib.format("~.1fK", [value / 1_000]) |> IO.iodata_to_binary()

      abs_val >= 1_000 ->
        :io_lib.format("~.0f", [Float.round(value, 0)]) |> IO.iodata_to_binary()

      true ->
        rounded = Float.round(value, 1)

        if Float.round(rounded, 0) == rounded do
          rounded |> round() |> Integer.to_string()
        else
          :erlang.float_to_binary(rounded, decimals: 1)
        end
    end
  end

  defp to_compact(value) do
    value
    |> numeric_value()
    |> case do
      nil -> "—"
      v -> to_compact(v)
    end
  end

  attr :latest, :float, default: nil
  attr :past, :float, default: nil

  defp delta_chip(assigns) do
    cond do
      is_nil(assigns.latest) or is_nil(assigns.past) ->
        ~H"""
        <span class="text-base-content/40">—</span>
        """

      assigns.past == 0 ->
        ~H"""
        <span class="text-base-content/40">∞</span>
        """

      true ->
        diff = assigns.latest - assigns.past
        pct = diff / assigns.past

        cls =
          cond do
            pct > 0.15 -> "bg-emerald-100 text-emerald-700 border border-emerald-200"
            pct > 0.03 -> "bg-emerald-50 text-emerald-600 border border-emerald-200"
            pct < -0.15 -> "bg-rose-100 text-rose-700 border border-rose-200"
            pct < -0.03 -> "bg-rose-50 text-rose-600 border border-rose-200"
            true -> "bg-base-100 text-base-content border border-base-200"
          end

        arrow =
          cond do
            diff > 0 -> "▲"
            diff < 0 -> "▼"
            true -> "■"
          end

        pct_str =
          pct
          |> Kernel.*(100.0)
          |> Float.round(1)
          |> :erlang.float_to_binary(decimals: 1)

        assigns =
          assigns
          |> Map.put(:cls, cls)
          |> Map.put(:arrow, arrow)
          |> Map.put(:pct_str, pct_str)
          |> Map.put(:diff, Float.round(diff, 1))

        ~H"""
        <span
          class={"inline-block px-1.5 py-0.5 rounded text-[10px] font-medium tabular-nums #{@cls}"}
          title={"Δ #{@diff} (#{@pct_str}%)"}
        >
          {@arrow} {@pct_str}%
        </span>
        """
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
