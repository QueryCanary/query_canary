defmodule QueryCanaryWeb.ReportLive.MetricDetailsComponent do
  use QueryCanaryWeb, :live_component

  alias Decimal
  alias QueryCanary.Reports.Report
  alias QueryCanaryWeb.Components.SQLEditor

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :ending_period, List.last(assigns.table_periods))

    ~H"""
    <div
      id="metric-details-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="metric-details-title"
      phx-window-keydown="close_metric_modal"
      phx-key="escape"
    >
      <div class="absolute inset-0 bg-base-content/45 backdrop-blur-sm" phx-click="close_metric_modal">
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
              class="h-56 w-full"
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
            <.metric_stat_card
              title="Latest"
              value={fmt(@selected_metric.latest, @selected_metric.opts)}
              subtitle={"Report window ending #{format_period(@ending_period, @report)}"}
            />
            <.metric_delta_stat_card
              title="Previous Period"
              latest={@selected_metric.latest}
              past={@selected_metric.previous_period}
              subtitle={"Compared with the prior #{timeline_bucket_label(@report)} bucket"}
            />
            <.metric_stat_card
              title="Average"
              value={fmt(@selected_metric.avg, @selected_metric.opts)}
              subtitle="Across the current report window"
            />
            <.metric_stat_card
              title="Base Metric"
              value={metric_granularity(@selected_metric.metric)}
              value_class="text-lg"
              subtitle={"Timeline: #{timeline_bucket_label(@report)}"}
            />
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
                      <%= if server = selected_metric_editor_server(
                                   @servers,
                                   @selected_metric_form,
                                   @selected_metric.metric
                                 ) do %>
                        <.live_component
                          module={SQLEditor}
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
                    <.input
                      field={@selected_metric_form[:granularity]}
                      type="select"
                      label="Base Granularity"
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
                  Backfill {@selected_metric.auto_backfill_label}
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
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :subtitle, :string, required: true
  attr :value_class, :string, default: "text-2xl"

  defp metric_stat_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
      <div class="text-xs uppercase tracking-wide text-base-content/50">{@title}</div>
      <div class={["mt-2 font-semibold tabular-nums", @value_class]}>{@value}</div>
      <div class="mt-1 text-xs text-base-content/60">{@subtitle}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :latest, :any, default: nil
  attr :past, :any, default: nil
  attr :subtitle, :string, required: true

  defp metric_delta_stat_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-200 bg-base-200/50 p-4">
      <div class="text-xs uppercase tracking-wide text-base-content/50">{@title}</div>
      <div class="mt-2">
        <.delta_chip latest={@latest} past={@past} />
      </div>
      <div class="mt-2 text-xs text-base-content/60">{@subtitle}</div>
    </div>
    """
  end

  defp timeline_bucket_label(%Report{settings: settings}) when is_map(settings) do
    case Map.get(settings, "timeline_bucket", "day") do
      "week" -> "weekly"
      "month" -> "monthly"
      _ -> "daily"
    end
  end

  defp timeline_bucket_label(_), do: "daily"

  defp format_day(nil), do: "—"
  defp format_day(day), do: Calendar.strftime(day, "%Y-%m-%d")

  defp format_period(nil, _report), do: "—"

  defp format_period(period, %Report{settings: settings}) when is_map(settings) do
    case Map.get(settings, "timeline_bucket", "day") do
      "week" -> "Week of #{format_day(period)}"
      "month" -> Calendar.strftime(period, "%b %Y")
      _ -> format_day(period)
    end
  end

  defp format_period(period, _report), do: format_day(period)

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

    if from_day == to_day, do: from_day, else: "#{from_day} → #{to_day}"
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

  defp fmt(nil, _opts), do: "—"
  defp fmt(value, opts) when is_number(value), do: fmt_number(value, opts)
  defp fmt(_value, _opts), do: "—"

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
      numeric -> to_compact(numeric)
    end
  end

  defp numeric_value(nil), do: nil
  defp numeric_value(%Decimal{} = dec), do: Decimal.to_float(dec)
  defp numeric_value(value) when is_integer(value), do: value * 1.0
  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(_), do: nil

  attr :latest, :any, default: nil
  attr :past, :any, default: nil

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
            pct > 0.15 -> "border border-emerald-200 bg-emerald-100 text-emerald-700"
            pct > 0.03 -> "border border-emerald-200 bg-emerald-50 text-emerald-600"
            pct < -0.15 -> "border border-rose-200 bg-rose-100 text-rose-700"
            pct < -0.03 -> "border border-rose-200 bg-rose-50 text-rose-600"
            true -> "border border-base-200 bg-base-100 text-base-content"
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
          |> assign(:cls, cls)
          |> assign(:arrow, arrow)
          |> assign(:pct_str, pct_str)
          |> assign(:diff, Float.round(diff, 1))

        ~H"""
        <span
          class={"inline-block rounded px-1.5 py-0.5 text-[10px] font-medium tabular-nums #{@cls}"}
          title={"Δ #{@diff} (#{@pct_str}%)"}
        >
          {@arrow} {@pct_str}%
        </span>
        """
    end
  end

  attr :change, :any, default: nil
  attr :opts, :map, required: true

  defp history_change_chip(assigns) do
    cond do
      is_nil(assigns.change) ->
        ~H"""
        <span class="text-base-content/40">—</span>
        """

      assigns.change > 0 ->
        ~H"""
        <span class="tabular-nums text-emerald-700">+{fmt(@change, @opts)}</span>
        """

      assigns.change < 0 ->
        ~H"""
        <span class="tabular-nums text-rose-700">{fmt(@change, @opts)}</span>
        """

      true ->
        ~H"""
        <span class="tabular-nums text-base-content/60">{fmt(@change, @opts)}</span>
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
