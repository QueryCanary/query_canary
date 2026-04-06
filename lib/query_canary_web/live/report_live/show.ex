defmodule QueryCanaryWeb.ReportLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics
  alias QueryCanary.Metrics.Metric
  alias QueryCanary.Reports
  alias QueryCanary.Reports.{Report, ReportGroup, ReportGroupMetric}
  alias QueryCanary.Servers
  alias Decimal

  on_mount {QueryCanaryWeb.UserAuth, :require_authenticated}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    metrics = Metrics.list_metrics_for_scope(socket.assigns.current_scope, preload: [:server])
    servers = Servers.list_servers(socket.assigns.current_scope)
    report = Reports.get_report!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:metrics, metrics)
     |> assign(:metrics_by_id, Map.new(metrics, &{&1.id, &1}))
     |> assign(:servers, servers)
     |> assign(:subscribed_metric_ids, MapSet.new())
     |> assign(:editing_group_id, nil)
     |> assign(:editing_metric_id, nil)
     |> assign(:adding_metric_group_id, nil)
     |> assign(:creating_metric_group_id, nil)
     |> assign(:selected_group_metric_id, nil)
     |> assign(:selected_metric, nil)
     |> assign(:selected_metric_form, nil)
     |> assign(:editing_selected_metric, false)
     |> assign(
       :new_metric_form,
       to_form(new_metric_changeset(default_new_metric_attrs()), as: :metric)
     )
     |> assign_report(report)
     |> reset_new_group_form()}
  end

  @impl true
  def handle_info({:metric_result_updated, metric_id}, socket) do
    if report_has_metric?(socket.assigns.report, metric_id) do
      {:noreply, refresh_report(socket)}
    else
      {:noreply, socket}
    end
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

    {:noreply,
     socket
     |> assign(:adding_metric_group_id, new_value)
     |> assign(:creating_metric_group_id, nil)}
  end

  def handle_event("start_create_metric", %{"id" => id}, socket) do
    group_id = parse_int(id)

    {:noreply,
     socket
     |> assign(:creating_metric_group_id, group_id)
     |> assign(:adding_metric_group_id, nil)
     |> assign(:selected_group_metric_id, nil)
     |> assign(:selected_metric, nil)
     |> assign(:selected_metric_form, nil)
     |> assign(:editing_selected_metric, false)
     |> assign(
       :new_metric_form,
       to_form(
         new_metric_changeset(default_new_metric_attrs(socket.assigns.report)),
         as: :metric
       )
     )}
  end

  def handle_event("cancel_create_metric", _params, socket) do
    {:noreply,
     socket
     |> assign(:creating_metric_group_id, nil)
     |> assign(
       :new_metric_form,
       to_form(new_metric_changeset(default_new_metric_attrs(socket.assigns.report)), as: :metric)
     )}
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

  def handle_event("open_metric_modal", %{"id" => id}, socket) do
    {:noreply, assign_selected_metric(socket, parse_int(id))}
  end

  def handle_event("validate_new_metric", %{"metric" => params}, socket) do
    changeset =
      params
      |> new_metric_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_metric_form, to_form(changeset, as: :metric))}
  end

  def handle_event(
        "create_metric_for_group",
        %{"metric" => params, "group_id" => group_id},
        socket
      ) do
    case find_group(socket.assigns.report, group_id) do
      %ReportGroup{} = group ->
        case Metrics.create_metric(params) do
          {:ok, metric} ->
            case Reports.add_metric_to_group(socket.assigns.current_scope, group, metric) do
              {:ok, _group_metric} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Metric created and added to #{group.name}")
                 |> assign_metric_catalog()
                 |> assign(:creating_metric_group_id, nil)
                 |> assign(
                   :new_metric_form,
                   to_form(
                     new_metric_changeset(default_new_metric_attrs(socket.assigns.report)),
                     as: :metric
                   )
                 )
                 |> refresh_report()}

              {:error, _changeset} ->
                {:noreply,
                 put_flash(
                   socket,
                   :error,
                   "Metric was created but could not be added to the group"
                 )}
            end

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             assign(
               socket,
               :new_metric_form,
               to_form(Map.put(changeset, :action, :insert), as: :metric)
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "move_metric_to_group",
        %{
          "metric_group_id" => metric_group_id,
          "target_group_id" => target_group_id
        } = params,
        socket
      ) do
    before_group_metric_id =
      params
      |> Map.get("before_group_metric_id")
      |> parse_int()

    case {find_group_metric(socket.assigns.report, metric_group_id),
          find_group(socket.assigns.report, target_group_id)} do
      {%ReportGroupMetric{} = group_metric, %ReportGroup{} = target_group} ->
        case Reports.move_metric_to_group(
               socket.assigns.current_scope,
               group_metric,
               target_group,
               before_group_metric_id: before_group_metric_id
             ) do
          {:ok, _} ->
            {:noreply, refresh_report(socket)}

          {:error, %Ecto.Changeset{} = changeset} ->
            message =
              changeset.errors
              |> Keyword.values()
              |> Enum.map_join(", ", fn {msg, _opts} -> msg end)

            {:noreply,
             put_flash(
               socket,
               :error,
               if(message == "", do: "Unable to move metric", else: message)
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Unable to move metric")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_selected_metric", _params, socket) do
    {:noreply, assign(socket, :editing_selected_metric, true)}
  end

  def handle_event("cancel_selected_metric_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_selected_metric, false)
     |> reset_selected_metric_form()}
  end

  def handle_event("validate_selected_metric", %{"metric" => params}, socket) do
    case socket.assigns.selected_metric do
      %{metric: %Metric{} = metric} ->
        changeset =
          metric
          |> Metric.changeset(params)
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:editing_selected_metric, true)
         |> assign(:selected_metric_form, to_form(changeset, as: :metric))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_selected_metric", %{"metric" => params}, socket) do
    case socket.assigns.selected_metric do
      %{metric: %Metric{} = metric} ->
        case Metrics.update_metric(metric, params) do
          {:ok, _updated_metric} ->
            {:noreply,
             socket
             |> put_flash(:info, "Metric updated")
             |> assign_metric_catalog()
             |> assign(:editing_selected_metric, false)
             |> refresh_report()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> assign(:editing_selected_metric, true)
             |> assign(:selected_metric_form, to_form(changeset, as: :metric))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("auto_backfill_selected_metric", _params, socket) do
    case socket.assigns.selected_metric do
      %{metric: %Metric{} = metric} ->
        {from_date, to_date, total_days} = auto_backfill_window(socket.assigns.report, metric)

        case Metrics.enqueue_backfill(metric.id, from_date, to_date) do
          {:ok, _job} ->
            {:noreply,
             put_flash(
               socket,
               :info,
               "Backfill enqueued for #{metric.name} across #{total_days} day(s)"
             )}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Unable to enqueue backfill")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_selected_metric", _params, socket) do
    case socket.assigns.selected_metric do
      %{group_metric_id: group_metric_id} ->
        case find_group_metric(socket.assigns.report, group_metric_id) do
          %ReportGroupMetric{} = gm ->
            case Reports.remove_metric_from_group(socket.assigns.current_scope, gm) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Metric removed")
                 |> assign(:editing_metric_id, nil)
                 |> assign(:selected_group_metric_id, nil)
                 |> assign(:selected_metric, nil)
                 |> assign(:selected_metric_form, nil)
                 |> assign(:editing_selected_metric, false)
                 |> refresh_report()}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Unable to remove metric")}
            end

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_metric_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_group_metric_id, nil)
     |> assign(:selected_metric, nil)
     |> assign(:selected_metric_form, nil)
     |> assign(:editing_selected_metric, false)}
  end

  defp refresh_report(socket) do
    report = Reports.get_report!(socket.assigns.current_scope, socket.assigns.report.id)
    assign_report(socket, report)
  end

  defp assign_metric_catalog(socket) do
    metrics = Metrics.list_metrics_for_scope(socket.assigns.current_scope, preload: [:server])

    socket
    |> assign(:metrics, metrics)
    |> assign(:metrics_by_id, Map.new(metrics, &{&1.id, &1}))
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
    |> subscribe_to_report_metrics(report)
    |> assign_selected_metric(socket.assigns.selected_group_metric_id)
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

  defp report_has_metric?(%Report{} = report, metric_id) do
    report.groups
    |> Enum.flat_map(& &1.group_metrics)
    |> Enum.any?(&(&1.metric_id == metric_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.fluid_app flash={@flash} current_scope={@current_scope}>
      <.header class="mb-2">
        {@report.name}
        <:subtitle>
          Default Range: {@report.default_range} • Timezone: {@report.timezone}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/reports"} class="btn btn-ghost btn-sm">
            <.icon name="hero-arrow-left" /> Back
          </.link>
          <.link navigate={~p"/reports/#{@report.id}/edit"} class="btn btn-primary btn-sm">
            Edit Details
          </.link>
        </:actions>
      </.header>

      <section class="space-y-3">
        <div class="space-y-2">
          <div class="flex flex-col gap-2 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <h2 class="text-base font-semibold tracking-tight">Report Overview</h2>
              <div class="text-[11px] text-base-content/60">
                Showing {length(@table_days)} day(s) ending {format_day(List.last(@table_days))}
              </div>
            </div>

            <.form
              for={@new_group_form}
              phx-submit="add_group"
              class="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-2"
            >
              <.input
                field={@new_group_form[:name]}
                placeholder="New group name"
                required
                class="min-w-[10rem] input-sm"
              />
              <.button type="submit" variant="primary-sm" class="sm:w-auto">
                Add Group
              </.button>
            </.form>
          </div>

          <div
            :if={!Enum.empty?(@table_rows)}
            id="report-metric-board"
            phx-hook="ReportMetricDrag"
            class="-mx-4 overflow-auto rounded-none border-y border-base-300 bg-base-100 shadow-sm sm:-mx-6 lg:-mx-8"
          >
            <table class="min-w-full border-collapse text-[10px] leading-none lg:text-[11px]">
              <thead class="bg-base-200 sticky top-0 z-20">
                <tr>
                  <th class="sticky left-0 z-30 bg-base-200 px-2 py-1.5 text-left font-medium text-base-content/70 border-b border-base-300 w-40 lg:w-44">
                    Metric
                  </th>
                  <%= for day <- @table_days do %>
                    <th class="px-0.5 py-1 text-center font-medium text-base-content/70 border-b border-base-300 w-8 lg:w-9">
                      <div class="flex flex-col items-center gap-px">
                        <span class="font-semibold tabular-nums">{format_day_compact(day)}</span>
                        <span class="text-[8px] font-normal uppercase text-base-content/45">
                          {day_of_week_initial(day)}
                        </span>
                      </div>
                    </th>
                  <% end %>
                  <th class="px-1 py-1 text-center font-medium text-base-content/70 border-b border-base-300 w-11 lg:w-12">
                    7d
                  </th>
                  <th class="px-1 py-1 text-center font-medium text-base-content/70 border-b border-base-300 w-11 lg:w-12">
                    Start
                  </th>
                  <th class="px-1 py-1 text-center font-medium text-base-content/70 border-b border-base-300 w-11 lg:w-12">
                    Avg
                  </th>
                </tr>
              </thead>
              <tbody>
                <%= for group <- @table_groups do %>
                  <% group_editing? = @editing_group_id == group.id %>
                  <% adding_metric? = @adding_metric_group_id == group.id %>
                  <tr>
                    <td
                      data-metric-drop-group-id={group.id}
                      class="sticky left-0 z-10 bg-base-200/90 backdrop-blur px-2 py-1.5 text-[9px] font-semibold uppercase tracking-[0.16em] text-base-content/60 border-t border-b border-base-300"
                      colspan={length(@table_days) + 4}
                    >
                      <div class="flex flex-col gap-1.5 lg:flex-row lg:items-center lg:justify-between">
                        <div class="flex flex-col gap-1.5 sm:flex-row sm:items-center sm:gap-2">
                          <%= if group_editing? do %>
                            <.form
                              for={%{}}
                              as={:group}
                              phx-submit="save_group"
                              class="flex flex-col gap-1.5 sm:flex-row sm:items-center sm:gap-2"
                            >
                              <input type="hidden" name="group[id]" value={group.id} />
                              <input
                                type="text"
                                name="group[name]"
                                value={group.name}
                                class="input input-xs w-full sm:w-52"
                                autofocus
                              />
                              <div class="flex gap-2">
                                <button type="submit" class="btn btn-xs btn-primary">
                                  Save
                                </button>
                                <button
                                  type="button"
                                  class="btn btn-xs btn-ghost"
                                  phx-click="cancel_group_edit"
                                >
                                  Cancel
                                </button>
                              </div>
                            </.form>
                          <% else %>
                            <div class="flex items-center gap-2">
                              <span class="text-xs font-semibold tracking-wide">{group.name}</span>
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
                            <form phx-submit="add_metric" class="flex flex-wrap gap-1.5 items-center">
                              <input type="hidden" name="add_metric[group_id]" value={group.id} />
                              <select
                                name="add_metric[metric_id]"
                                class="select select-bordered select-xs min-w-[9rem]"
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
                              <button
                                type="button"
                                class="btn btn-xs btn-ghost sm:btn-sm"
                                phx-click="start_create_metric"
                                phx-value-id={group.id}
                              >
                                New metric
                              </button>
                            </form>
                          <% else %>
                            <div class="flex items-center gap-2">
                              <button
                                type="button"
                                class="btn btn-ghost btn-xs"
                                phx-click="toggle_add_metric"
                                phx-value-id={group.id}
                              >
                                <.icon name="hero-plus" class="h-4 w-4" />
                                <span class="sr-only">Add metric</span>
                              </button>
                              <button
                                type="button"
                                class="btn btn-ghost btn-xs"
                                phx-click="start_create_metric"
                                phx-value-id={group.id}
                              >
                                New metric
                              </button>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    </td>
                  </tr>

                  <% rows = Enum.filter(@table_rows, &(&1.group_id == group.id)) %>

                  <%= if Enum.empty?(rows) do %>
                    <tr>
                      <td
                        class="sticky left-0 z-10 bg-base-100 px-2 py-1.5 text-[11px] text-base-content/60 border-b border-base-200"
                        colspan={length(@table_days) + 4}
                      >
                        No metrics in this group yet.
                      </td>
                    </tr>
                  <% else %>
                    <%= for row <- rows do %>
                      <tr
                        class="hover:bg-base-200/30"
                        data-metric-row-id={row.group_metric_id}
                        data-metric-drop-group-id={row.group_id}
                        data-metric-drop-before-id={row.group_metric_id}
                      >
                        <td class="sticky left-0 z-10 bg-base-100 px-2 py-1 font-medium text-base-content border-b border-base-200">
                          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-2">
                            <div class="flex items-center gap-2">
                              <span
                                draggable="true"
                                data-draggable-metric-id={row.group_metric_id}
                                data-metric-drag-handle
                                class="inline-flex cursor-grab select-none items-center rounded px-1 py-0.5 text-base-content/35 hover:bg-base-200 hover:text-base-content/60 active:cursor-grabbing"
                                title="Drag to another group"
                              >
                                <.icon name="hero-bars-3" class="h-3.5 w-3.5" />
                              </span>
                              <button
                                type="button"
                                id={"metric-title-#{row.group_metric_id}"}
                                class="truncate text-left link link-hover font-medium text-[11px] lg:text-xs"
                                phx-click="open_metric_modal"
                                phx-value-id={row.group_metric_id}
                              >
                                {row.display_name}
                              </button>
                            </div>
                          </div>
                        </td>

                        <%= for day <- @table_days do %>
                          <% value = Map.get(row.values, day) %>
                          <% cls = heat_class(value, row.min, row.max, row.avg) %>
                          <td
                            class={"relative px-0.5 py-0.5 text-center align-middle border-b border-base-200 #{cls}"}
                            title={"#{row.display_name} #{format_day(day)}: #{fmt(value, row.opts)}"}
                          >
                            <div class="font-medium tabular-nums text-[9px] lg:text-[10px]">
                              {fmt_compact(value, row.opts)}
                            </div>
                            <div class="absolute inset-0 pointer-events-none">
                              <div class={"h-full w-full opacity-15 " <> heat_bg_color(value, row.min, row.max, row.avg)}>
                              </div>
                            </div>
                          </td>
                        <% end %>

                        <td class="px-1 py-0.5 text-center border-b border-base-200">
                          <.delta_chip latest={row.latest} past={row.week_ago} />
                        </td>
                        <td class="px-1 py-0.5 text-center border-b border-base-200">
                          <.delta_chip latest={row.latest} past={row.fortnight} />
                        </td>
                        <td class="px-1 py-0.5 text-center border-b border-base-200 text-base-content/70 tabular-nums">
                          {fmt(row.avg, row.opts)}
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

          <div class="flex items-center gap-3 pt-0.5 text-[9px] text-base-content/55">
            <div class="flex items-center gap-1">
              <span class="inline-block h-2.5 w-4 rounded bg-emerald-200"></span> High
            </div>
            <div class="flex items-center gap-1">
              <span class="inline-block h-2.5 w-4 rounded border border-base-300 bg-base-100"></span>
              Mid
            </div>
            <div class="flex items-center gap-1">
              <span class="inline-block h-2.5 w-4 rounded bg-rose-200"></span> Low
            </div>
          </div>
        </div>
      </section>

      <div
        :if={@selected_metric}
        id="metric-details-modal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
        role="dialog"
        aria-modal="true"
        aria-labelledby="metric-details-title"
        phx-window-keydown="close_metric_modal"
        phx-key="escape"
      >
        <div
          class="absolute inset-0 bg-base-content/45 backdrop-blur-sm"
          phx-click="close_metric_modal"
        >
        </div>

        <div class="relative z-10 w-full max-w-4xl overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-2xl">
          <div class="flex items-start justify-between gap-4 border-b border-base-200 px-6 py-5">
            <div class="space-y-2">
              <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                Metric Details
              </div>
              <h3 id="metric-details-title" class="text-2xl font-semibold tracking-tight">
                {@selected_metric.display_name}
              </h3>
              <div class="flex flex-wrap gap-2 text-xs text-base-content/70">
                <span class="badge badge-outline">
                  Group: {@selected_metric.group_name}
                </span>
                <span class="badge badge-outline">
                  Metric: {metric_name(@selected_metric.metric, @selected_metric.metric_id)}
                </span>
                <span class="badge badge-outline">
                  Server: {metric_server_name(@selected_metric.metric)}
                </span>
              </div>
            </div>

            <div class="flex items-center gap-2">
              <button
                :if={@selected_metric.metric}
                id="edit-metric-details"
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click={
                  if @editing_selected_metric,
                    do: "cancel_selected_metric_edit",
                    else: "edit_selected_metric"
                }
              >
                <.icon :if={!@editing_selected_metric} name="hero-pencil-square" class="h-4 w-4" />
                <.icon :if={@editing_selected_metric} name="hero-x-mark" class="h-4 w-4" />
                {if @editing_selected_metric, do: "Cancel edit", else: "Edit metric"}
              </button>

              <button
                :if={@selected_metric}
                id="remove-metric-from-report"
                type="button"
                class="btn btn-error btn-outline btn-sm"
                phx-click="remove_selected_metric"
                data-confirm="Remove this metric from the report?"
              >
                <.icon name="hero-trash" class="h-4 w-4" /> Remove
              </button>

              <button
                id="close-metric-details"
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="close_metric_modal"
              >
                <.icon name="hero-x-mark" class="h-5 w-5" />
              </button>
            </div>
          </div>

          <div class="max-h-[80vh] overflow-y-auto px-6 py-5">
            <div
              :if={@selected_metric.chart_data}
              class="mb-4 rounded-xl border border-base-200 bg-base-200/30 p-3"
            >
              <canvas
                id={"metric-history-chart-#{@selected_metric.metric_id}"}
                class="w-full h-56"
                phx-hook="CheckChart"
                data-labels={Jason.encode!(@selected_metric.chart_data.labels)}
                data-values={Jason.encode!(@selected_metric.chart_data.values)}
                data-success={Jason.encode!(@selected_metric.chart_data.success)}
                data-average={Jason.encode!(@selected_metric.chart_data.average)}
                data-alert-threshold={Jason.encode!(@selected_metric.chart_data.alert_threshold)}
                data-alert-type={@selected_metric.chart_data.alert_type}
              >
              </canvas>
            </div>

            <div class="grid gap-3 md:grid-cols-4">
              <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
                <div class="text-xs uppercase tracking-wide text-base-content/50">Latest</div>
                <div class="mt-2 text-2xl font-semibold tabular-nums">
                  {fmt(@selected_metric.latest, @selected_metric.opts)}
                </div>
                <div class="mt-1 text-xs text-base-content/60">
                  Report window ending {format_day(List.last(@table_days))}
                </div>
              </div>

              <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
                <div class="text-xs uppercase tracking-wide text-base-content/50">7d Change</div>
                <div class="mt-2">
                  <.delta_chip latest={@selected_metric.latest} past={@selected_metric.week_ago} />
                </div>
                <div class="mt-2 text-xs text-base-content/60">
                  Compared with the value from 7 periods earlier
                </div>
              </div>

              <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
                <div class="text-xs uppercase tracking-wide text-base-content/50">Average</div>
                <div class="mt-2 text-2xl font-semibold tabular-nums">
                  {fmt(@selected_metric.avg, @selected_metric.opts)}
                </div>
                <div class="mt-1 text-xs text-base-content/60">
                  Across the current report window
                </div>
              </div>

              <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
                <div class="text-xs uppercase tracking-wide text-base-content/50">Granularity</div>
                <div class="mt-2 text-lg font-semibold">
                  {metric_granularity(@selected_metric.metric)}
                </div>
                <div class="mt-1 text-xs text-base-content/60">
                  Schedule: {metric_schedule(@selected_metric.metric)}
                </div>
              </div>
            </div>

            <div class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.25fr)]">
              <div class="space-y-4">
                <div class="rounded-xl border border-base-200 p-4">
                  <div class="flex items-center justify-between gap-3">
                    <h4 class="text-sm font-semibold">Metric configuration</h4>
                    <span :if={@editing_selected_metric} class="badge badge-outline badge-primary">
                      Editing
                    </span>
                  </div>

                  <%= if @editing_selected_metric and @selected_metric_form do %>
                    <.form
                      id="selected-metric-form"
                      for={@selected_metric_form}
                      phx-change="validate_selected_metric"
                      phx-submit="save_selected_metric"
                      class="mt-4 space-y-3"
                    >
                      <.input field={@selected_metric_form[:name]} label="Name" />
                      <.input
                        field={@selected_metric_form[:description]}
                        type="textarea"
                        label="Description"
                        rows="3"
                      />
                      <div class="space-y-1">
                        <label class="label text-sm font-medium">SQL</label>
                        <%= if server = selected_metric_editor_server(@servers, @selected_metric_form, @selected_metric.metric) do %>
                          <.live_component
                            module={QueryCanaryWeb.Components.SQLEditor}
                            id={
                              selected_metric_editor_id(
                                @selected_metric.metric_id,
                                @selected_metric_form
                              )
                            }
                            server={server}
                            input_name={@selected_metric_form[:sql].name}
                            value={@selected_metric_form[:sql].value || ""}
                          />
                        <% else %>
                          <.input field={@selected_metric_form[:sql]} type="textarea" rows="6" />
                        <% end %>
                      </div>
                      <.input field={@selected_metric_form[:schedule]} label="Cron (e.g. * * * * *)" />
                      <.input
                        field={@selected_metric_form[:granularity]}
                        type="select"
                        label="Granularity"
                        options={granularity_options()}
                      />
                      <.input field={@selected_metric_form[:timezone]} label="Timezone" />
                      <.input
                        field={@selected_metric_form[:server_id]}
                        type="select"
                        label="Server"
                        options={server_options(@servers)}
                      />
                      <.input field={@selected_metric_form[:enabled]} type="checkbox" label="Enabled" />

                      <div class="flex items-center gap-2 pt-2">
                        <.button type="submit" variant="primary-sm">Save changes</.button>
                        <button
                          type="button"
                          class="btn btn-ghost btn-sm"
                          phx-click="cancel_selected_metric_edit"
                        >
                          Cancel
                        </button>
                      </div>
                    </.form>
                  <% else %>
                    <dl class="mt-4 space-y-3 text-sm">
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/50">Name</dt>
                        <dd class="mt-1 text-base-content/80">
                          {metric_name(@selected_metric.metric, @selected_metric.metric_id)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/50">
                          Description
                        </dt>
                        <dd class="mt-1 text-base-content/80">
                          {metric_description(@selected_metric.metric)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/50">Timezone</dt>
                        <dd class="mt-1 text-base-content/80">
                          {metric_timezone(@selected_metric.metric)}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs uppercase tracking-wide text-base-content/50">SQL</dt>
                        <dd class="mt-1">
                          <pre class="overflow-x-auto rounded-lg bg-base-200 px-3 py-3 text-sm"><code class="language-sql">{metric_sql(@selected_metric.metric)}</code></pre>
                        </dd>
                      </div>
                    </dl>
                  <% end %>
                </div>
              </div>

              <div class="rounded-xl border border-base-200 p-4">
                <div class="flex items-center justify-between gap-3">
                  <div>
                    <h4 class="text-sm font-semibold">Previous values</h4>
                    <p class="mt-1 text-xs text-base-content/60">
                      Most recent stored samples for this metric
                    </p>
                  </div>
                  <button
                    :if={@selected_metric.metric}
                    id="metric-auto-backfill"
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="auto_backfill_selected_metric"
                  >
                    Backfill {auto_backfill_label(@report, @selected_metric.metric)}
                  </button>
                </div>

                <div :if={Enum.empty?(@selected_metric.history)} class="alert alert-info mt-4 text-sm">
                  No previous values have been stored for this metric yet.
                </div>

                <div :if={!Enum.empty?(@selected_metric.history)} class="mt-4 overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Window</th>
                        <th class="text-right">Value</th>
                        <th class="text-right">Change</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for entry <- @selected_metric.history do %>
                        <tr>
                          <td>
                            <div class="font-medium">
                              {history_window_label(entry, @report.timezone)}
                            </div>
                            <div class="text-xs text-base-content/60">
                              {history_timestamp_label(entry, @report.timezone)}
                            </div>
                          </td>
                          <td class="text-right font-medium tabular-nums">
                            {fmt(entry.value, @selected_metric.opts)}
                          </td>
                          <td class="text-right">
                            <.history_change_chip change={entry.change} opts={@selected_metric.opts} />
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={creating_group = creating_metric_group(@report, @creating_metric_group_id)}
        id="new-metric-modal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-metric-title"
        phx-window-keydown="cancel_create_metric"
        phx-key="escape"
      >
        <div
          class="absolute inset-0 bg-base-content/45 backdrop-blur-sm"
          phx-click="cancel_create_metric"
        >
        </div>

        <div class="relative z-10 w-full max-w-3xl overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-2xl">
          <div class="flex items-start justify-between gap-4 border-b border-base-200 px-6 py-5">
            <div class="space-y-2">
              <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                New Metric
              </div>
              <h3 id="new-metric-title" class="text-2xl font-semibold tracking-tight">
                Create metric in {creating_group.name}
              </h3>
              <p class="text-sm text-base-content/60">
                Save a new metric and add it directly to this report group.
              </p>
            </div>

            <button
              id="close-new-metric-modal"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="cancel_create_metric"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>

          <div class="max-h-[80vh] overflow-y-auto px-6 py-5">
            <.form
              id={"new-metric-form-#{creating_group.id}"}
              for={@new_metric_form}
              phx-change="validate_new_metric"
              phx-submit="create_metric_for_group"
              class="space-y-3"
            >
              <input type="hidden" name="group_id" value={creating_group.id} />
              <div class="grid gap-3 md:grid-cols-2">
                <.input field={@new_metric_form[:name]} label="Name" />
                <.input
                  field={@new_metric_form[:server_id]}
                  type="select"
                  label="Server"
                  options={server_options(@servers)}
                />
              </div>
              <.input
                field={@new_metric_form[:description]}
                type="textarea"
                label="Description"
                rows="2"
              />
              <.input field={@new_metric_form[:sql]} type="textarea" label="SQL" rows="6" />
              <div class="grid gap-3 md:grid-cols-3">
                <.input field={@new_metric_form[:schedule]} label="Cron (e.g. * * * * *)" />
                <.input
                  field={@new_metric_form[:granularity]}
                  type="select"
                  label="Granularity"
                  options={granularity_options()}
                />
                <.input field={@new_metric_form[:timezone]} label="Timezone" />
              </div>
              <.input field={@new_metric_form[:enabled]} type="checkbox" label="Enabled" />

              <div class="flex items-center gap-2 pt-2">
                <.button type="submit" variant="primary-sm">Create metric</.button>
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_create_metric">
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.fluid_app>
    """
  end

  defp reset_new_group_form(socket) do
    assign(socket, :new_group_form, to_form(%{"name" => ""}, as: :group))
  end

  defp subscribe_to_report_metrics(socket, %Report{} = report) do
    if connected?(socket) do
      metric_ids =
        report.groups
        |> Enum.flat_map(& &1.group_metrics)
        |> Enum.map(& &1.metric_id)
        |> MapSet.new()

      new_metric_ids = MapSet.difference(metric_ids, socket.assigns.subscribed_metric_ids)

      if MapSet.size(new_metric_ids) > 0 do
        new_metric_ids
        |> MapSet.to_list()
        |> Metrics.subscribe_metric_results()
      end

      assign(
        socket,
        :subscribed_metric_ids,
        MapSet.union(socket.assigns.subscribed_metric_ids, metric_ids)
      )
    else
      socket
    end
  end

  defp build_table_state(report, metric_results, metrics_by_id) do
    tz = report.timezone || "Etc/UTC"
    max_days = effective_window_days(report)

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
          metric: metric,
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
    today = DateTime.now!(report.timezone || "Etc/UTC") |> DateTime.to_date()

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

  defp effective_window_days(%Report{} = report) do
    max(range_to_days(report.default_range || "30d"), minimum_report_window_days(report))
  end

  defp minimum_report_window_days(%Report{} = report) do
    report.groups
    |> Enum.flat_map(& &1.group_metrics)
    |> Enum.map(fn group_metric ->
      case group_metric.metric do
        %Metric{granularity: granularity} -> minimum_granularity_window_days(granularity)
        _ -> 1
      end
    end)
    |> Enum.max(fn -> 1 end)
  end

  defp minimum_granularity_window_days("minute"), do: 1
  defp minimum_granularity_window_days("hour"), do: 7
  defp minimum_granularity_window_days("day"), do: 30
  defp minimum_granularity_window_days("week"), do: 90
  defp minimum_granularity_window_days("month"), do: 90
  defp minimum_granularity_window_days(_), do: 30

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
          group.group_metrics |> Enum.map(& &1.metric_id) |> MapSet.new()
      end

    metrics_by_id
    |> Map.values()
    |> Enum.reject(&MapSet.member?(used_ids, &1.id))
    |> Enum.sort_by(& &1.name)
  end

  defp creating_metric_group(%Report{} = report, group_id) when is_integer(group_id) do
    Enum.find(report.groups, &(&1.id == group_id))
  end

  defp creating_metric_group(_report, _group_id), do: nil

  defp assign_selected_metric(socket, nil) do
    socket
    |> assign(:selected_group_metric_id, nil)
    |> assign(:selected_metric, nil)
    |> assign(:selected_metric_form, nil)
    |> assign(:editing_selected_metric, false)
  end

  defp assign_selected_metric(socket, group_metric_id) when is_integer(group_metric_id) do
    case Enum.find(socket.assigns.table_rows, &(&1.group_metric_id == group_metric_id)) do
      nil ->
        assign_selected_metric(socket, nil)

      row ->
        {from_ts, to_ts} = report_chart_window(socket.assigns.table_days, socket.assigns.report)

        metric_results =
          Metrics.list_metric_results(
            row.metric_id,
            from_ts: from_ts,
            to_ts: to_ts,
            limit: chart_point_limit(row.metric, length(socket.assigns.table_days)),
            order: :desc
          )

        history = build_history_entries(metric_results)

        changeset = selected_metric_changeset(row.metric)

        assign(socket,
          selected_group_metric_id: group_metric_id,
          selected_metric:
            row
            |> Map.put(:history, history)
            |> Map.put(
              :chart_data,
              build_metric_chart_data(metric_results, socket.assigns.report.timezone)
            ),
          selected_metric_form: to_form(changeset, as: :metric),
          editing_selected_metric: false
        )
    end
  end

  defp reset_selected_metric_form(
         %{assigns: %{selected_metric: %{metric: %Metric{} = metric}}} = socket
       ) do
    assign(socket, :selected_metric_form, to_form(selected_metric_changeset(metric), as: :metric))
  end

  defp reset_selected_metric_form(socket), do: assign(socket, :selected_metric_form, nil)

  defp selected_metric_changeset(%Metric{} = metric), do: Metric.changeset(metric, %{})
  defp selected_metric_changeset(_), do: Metric.changeset(%Metric{}, %{})

  defp build_history_entries(results) do
    entries =
      Enum.map(results, fn result ->
        %{
          from_ts: result.from_ts,
          to_ts: result.to_ts,
          value: numeric_value(result.value)
        }
      end)

    Enum.with_index(entries)
    |> Enum.map(fn {entry, idx} ->
      previous_entry = Enum.at(entries, idx + 1)
      Map.put(entry, :change, history_change(entry.value, previous_entry && previous_entry.value))
    end)
  end

  defp build_metric_chart_data([], _timezone), do: nil

  defp build_metric_chart_data(results, timezone) do
    chronological_results = Enum.reverse(results)

    labels =
      Enum.map(chronological_results, fn result ->
        result
        |> chart_label_for_metric_result(timezone || "Etc/UTC")
      end)

    values =
      Enum.map(chronological_results, fn result ->
        numeric_value(result.value)
      end)

    numeric_values = Enum.filter(values, &is_number/1)

    average =
      case numeric_values do
        [] -> nil
        nums -> Enum.sum(nums) / length(nums)
      end

    %{
      labels: labels,
      values: values,
      success: Enum.map(values, fn _ -> 1 end),
      average: average,
      alert_threshold: %{upper: nil, lower: nil},
      alert_type: ""
    }
  end

  defp chart_label_for_metric_result(result, timezone) do
    from_local = DateTime.shift_zone!(result.from_ts, timezone)
    to_local = DateTime.shift_zone!(result.to_ts, timezone)
    span_seconds = DateTime.diff(to_local, from_local)

    cond do
      span_seconds <= 3_600 ->
        Calendar.strftime(from_local, "%m-%d %H:%M")

      span_seconds <= 86_400 ->
        Calendar.strftime(from_local, "%m-%d")

      true ->
        Calendar.strftime(from_local, "%Y-%m-%d")
    end
  end

  defp report_chart_window([], %Report{} = report) do
    tz = report.timezone || "Etc/UTC"
    today = DateTime.now!(tz) |> DateTime.to_date()
    report_chart_window([today], report)
  end

  defp report_chart_window(days, %Report{} = report) do
    tz = report.timezone || "Etc/UTC"
    first_day = List.first(days)
    last_day = List.last(days)

    from_ts = DateTime.new!(first_day, ~T[00:00:00], tz) |> DateTime.shift_zone!("Etc/UTC")

    to_ts =
      last_day
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], tz)
      |> DateTime.shift_zone!("Etc/UTC")

    {from_ts, to_ts}
  end

  defp chart_point_limit(nil, day_count), do: max(day_count, 30)

  defp chart_point_limit(%Metric{granularity: "minute"}, day_count),
    do: min(max(day_count * 24 * 60, 60), 1000)

  defp chart_point_limit(%Metric{granularity: "hour"}, day_count),
    do: min(max(day_count * 24, 24), 1000)

  defp chart_point_limit(%Metric{granularity: "day"}, day_count), do: max(day_count, 30)

  defp chart_point_limit(%Metric{granularity: "week"}, day_count),
    do: max(div(day_count, 7) + 2, 12)

  defp chart_point_limit(%Metric{granularity: "month"}, day_count),
    do: max(div(day_count, 30) + 2, 12)

  defp chart_point_limit(%Metric{}, day_count), do: max(day_count, 30)

  defp history_change(nil, _previous_value), do: nil
  defp history_change(_value, nil), do: nil
  defp history_change(value, previous_value), do: value - previous_value

  defp format_day(nil), do: "—"
  defp format_day(d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_day_compact(d), do: Calendar.strftime(d, "%d")
  defp day_of_week_initial(d), do: Calendar.strftime(d, "%a") |> String.first()

  defp history_window_label(entry, timezone) do
    from_day =
      entry.from_ts
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
      |> format_day()

    to_day =
      entry.to_ts
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
      |> Date.add(-1)
      |> format_day()

    if from_day == to_day do
      from_day
    else
      "#{from_day} → #{to_day}"
    end
  end

  defp history_timestamp_label(entry, timezone) do
    from_ts = Calendar.strftime(DateTime.shift_zone!(entry.from_ts, timezone), "%b %-d, %Y %H:%M")
    to_ts = Calendar.strftime(DateTime.shift_zone!(entry.to_ts, timezone), "%b %-d, %Y %H:%M")
    "#{from_ts} to #{to_ts}"
  end

  defp metric_name(nil, metric_id), do: "Metric #{metric_id}"
  defp metric_name(metric, _metric_id), do: metric.name

  defp metric_server_name(nil), do: "Unknown server"
  defp metric_server_name(%{server: %{name: name}}), do: name
  defp metric_server_name(%{server_id: nil}), do: "Unknown server"
  defp metric_server_name(%{server_id: server_id}), do: "Server ##{server_id}"

  defp metric_granularity(nil), do: "—"
  defp metric_granularity(metric), do: metric.granularity

  defp metric_schedule(nil), do: "—"
  defp metric_schedule(metric), do: metric.schedule

  defp metric_timezone(nil), do: "—"
  defp metric_timezone(metric), do: metric.timezone || "Etc/UTC"

  defp metric_description(nil), do: "No description provided."
  defp metric_description(%{description: nil}), do: "No description provided."
  defp metric_description(%{description: ""}), do: "No description provided."
  defp metric_description(metric), do: metric.description

  defp metric_sql(nil), do: "SQL unavailable"
  defp metric_sql(metric), do: metric.sql

  defp granularity_options, do: ["minute", "hour", "day", "week", "month"]

  defp server_options(servers) do
    Enum.map(servers, fn server -> {server.name, server.id} end)
  end

  defp selected_metric_editor_id(metric_id, form) do
    "selected-metric-sql-editor-#{metric_id}-#{selected_metric_server_id(form) || "none"}"
  end

  defp selected_metric_editor_server(servers, form, metric) do
    server_id = selected_metric_server_id(form) || (metric && metric.server_id)
    Enum.find(servers, &(&1.id == server_id))
  end

  defp selected_metric_server_id(nil), do: nil

  defp selected_metric_server_id(form) do
    form[:server_id].value
    |> parse_int()
  end

  defp default_new_metric_attrs(report \\ nil) do
    %{
      "name" => "",
      "description" => "",
      "sql" => "",
      "schedule" => "* * * * *",
      "granularity" => "day",
      "timezone" => if(report, do: report.timezone || "Etc/UTC", else: "Etc/UTC"),
      "enabled" => true,
      "server_id" => nil
    }
  end

  defp new_metric_changeset(attrs) do
    Metric.changeset(%Metric{}, attrs)
  end

  defp auto_backfill_window(%Report{} = report, %Metric{} = metric) do
    end_date = report_end_date(report, metric)

    total_days =
      max(range_to_days(report.default_range), minimum_backfill_days(metric.granularity))

    start_date = Date.add(end_date, -(total_days - 1))
    {start_date, end_date, total_days}
  end

  defp auto_backfill_label(%Report{} = report, %Metric{} = metric) do
    {_from_date, _to_date, total_days} = auto_backfill_window(report, metric)

    cond do
      total_days >= 365 and rem(total_days, 365) == 0 -> "#{div(total_days, 365)}y"
      total_days >= 30 and rem(total_days, 30) == 0 -> "#{div(total_days, 30)}mo"
      total_days >= 7 and rem(total_days, 7) == 0 -> "#{div(total_days, 7)}w"
      true -> "#{total_days}d"
    end
  end

  defp report_end_date(%Report{} = report, %Metric{} = metric) do
    tz = metric.timezone || report.timezone || "Etc/UTC"
    today = DateTime.now!(tz) |> DateTime.to_date()

    case report.default_range do
      "yesterday" -> Date.add(today, -1)
      _ -> today
    end
  end

  defp minimum_backfill_days("minute"), do: 1
  defp minimum_backfill_days("hour"), do: 3
  defp minimum_backfill_days("day"), do: 30
  defp minimum_backfill_days("week"), do: 84
  defp minimum_backfill_days("month"), do: 365
  defp minimum_backfill_days(_), do: 30

  defp heat_class(v, min, max, avg) do
    case heat_signal(v, min, max, avg) do
      :high -> "text-emerald-700"
      :mid_high -> "text-emerald-600"
      :mid_low -> "text-rose-600"
      :low -> "text-rose-700"
      :neutral -> "text-base-content/70"
      :empty -> "text-base-content/40"
    end
  end

  defp heat_bg_color(v, min, max, avg) do
    case heat_signal(v, min, max, avg) do
      :high -> "bg-emerald-300"
      :mid_high -> "bg-emerald-200"
      :mid_low -> "bg-rose-200"
      :low -> "bg-rose-300"
      _ -> "bg-base-100"
    end
  end

  defp heat_signal(nil, _min, _max, _avg), do: :empty
  defp heat_signal(_v, nil, _max, _avg), do: :neutral
  defp heat_signal(_v, _min, nil, _avg), do: :neutral
  defp heat_signal(_v, min, max, _avg) when max == min, do: :neutral

  defp heat_signal(v, min, max, avg) do
    span = max - min
    scale = Enum.max([abs(min), abs(max), abs(avg || 0.0)])

    cond do
      span <= 0 ->
        :neutral

      # Small-value metrics shouldn't look alarming unless the move is truly meaningful.
      scale < 5.0 and span < 5.0 ->
        :neutral

      true ->
        center = avg || (min + max) / 2.0
        diff = v - center
        diff_abs = abs(diff)
        significant_move = max(span * 0.35, max(abs(center) * 0.75, 1.0))

        cond do
          diff_abs < significant_move ->
            :neutral

          diff > 0 ->
            if diff_abs >= significant_move * 1.5, do: :high, else: :mid_high

          true ->
            if diff_abs >= significant_move * 1.5, do: :low, else: :mid_low
        end
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
        value |> Float.round(0) |> round() |> Integer.to_string()

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

  attr :change, :float, default: nil
  attr :opts, :map, required: true

  defp history_change_chip(assigns) do
    cond do
      is_nil(assigns.change) ->
        ~H"""
        <span class="text-base-content/40">—</span>
        """

      assigns.change > 0 ->
        ~H"""
        <span class="text-emerald-700 tabular-nums">+{fmt(@change, @opts)}</span>
        """

      assigns.change < 0 ->
        ~H"""
        <span class="text-rose-700 tabular-nums">{fmt(@change, @opts)}</span>
        """

      true ->
        ~H"""
        <span class="text-base-content/60 tabular-nums">{fmt(@change, @opts)}</span>
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
