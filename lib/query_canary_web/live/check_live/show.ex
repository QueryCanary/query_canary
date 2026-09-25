defmodule QueryCanaryWeb.CheckLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks
  alias QueryCanary.Checks.{ChartData, CheckResult}

  import QueryCanaryWeb.Components.CheckAnalysis

  on_mount {QueryCanaryWeb.CheckAuth, :view}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <div class="badge badge-soft badge-info">
          <.icon name="hero-circle-stack" /> {@check.server.name}
        </div>
        {@check.name}
        <:subtitle>
          Last run: {@last_run} • Next run: {@next_run} • Schedule: {@check.schedule}
        </:subtitle>
        <:actions>
          <.button
            :if={
              @can_edit? && @check.enabled && match?(%CheckResult{success: false}, @latest_analysis)
            }
            id="rerun-check"
            phx-click="rerun_check"
            phx-disable-with="Queuing…"
          >
            <.icon name="hero-arrow-path" /> Rerun check
          </.button>
          <.button :if={@can_edit?} navigate={~p"/checks"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            :if={@can_edit?}
            variant="primary"
            navigate={~p"/checks/#{@check}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit check
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">SQL Query</h2>
          <pre class="bg-base-300 text-sm p-4 rounded-lg overflow-x-auto font-mono"><code class="language-sql">{@check.query}</code></pre>
        </div>
      </div>

      <.check_analysis result={@latest_analysis} />

      <div class="card bg-base-200">
        <div class="card-body space-y-4">
          <h2 class="card-title">Result History</h2>

          <%= if length(@results) > 0 do %>
            <canvas
              id="results-chart"
              class="w-full h-64"
              phx-hook="CheckChart"
              data-chart={Jason.encode!(@chart_data)}
            >
            </canvas>

            <div class="grid grid-cols-4 gap-2 text-sm mt-2 text-center">
              <div class="stat p-0">
                <div class="stat-title text-xs">Avg Value</div>
                <div class="stat-value text-lg">{format_number(@stats.avg_value)}</div>
              </div>
              <div class="stat p-0">
                <div class="stat-title text-xs">Success Rate</div>
                <div class="stat-value text-lg">{@stats.success_rate}%</div>
              </div>
              <div class="stat p-0">
                <div class="stat-title text-xs">Alert Rate</div>
                <div class="stat-value text-lg">{@stats.alert_rate}%</div>
              </div>
              <div class="stat p-0">
                <div class="stat-title text-xs">Avg Response</div>
                <div class="stat-value text-lg">{@stats.avg_time} ms</div>
              </div>
            </div>

            <.table id="table-results" rows={@results}>
              <:col :let={result} label="Ran At">{format_datetime(result.inserted_at)}</:col>
              <:col :let={result} label="Fields">
                {format_result_fields(result)}
              </:col>
              <:col :let={result} label="Alert Type">
                <span class={result_status_class(result)} title={result.error}>
                  {result_status_label(result)}
                </span>
              </:col>
              <:col :let={result} label="Duration">{result.time_taken} ms</:col>
            </.table>
          <% else %>
            <div class="alert mt-3">No result history available</div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => _id}, _session, socket) do
    # Check comes from the on_mount
    check = socket.assigns.check
    if connected?(socket), do: Checks.subscribe_check_results(check.id)
    recent_results = Checks.get_recent_check_results(check, 48)

    latest_result =
      if Enum.empty?(recent_results),
        do: nil,
        else: hd(recent_results)

    last_run =
      if Enum.empty?(recent_results),
        do: "No previous run",
        else:
          hd(recent_results) |> Map.get(:inserted_at) |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

    next_run =
      Crontab.CronExpression.Parser.parse!(check.schedule)
      |> Crontab.Scheduler.get_next_run_date!()
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

    {:ok,
     socket
     |> assign(:page_title, check.name)
     |> assign(:check, check)
     |> assign(:can_edit?, Checks.can_perform?(:edit, socket.assigns.current_scope, check))
     |> assign(:latest_analysis, latest_result)
     |> assign(:results, recent_results)
     |> assign(:last_run, last_run)
     |> assign(:next_run, next_run)
     |> assign(:chart_data, ChartData.from_results(recent_results))
     |> assign(:stats, calculate_stats(recent_results))}
  end

  @impl true
  def handle_event("rerun_check", _params, socket) do
    case Checks.rerun_check(socket.assigns.current_scope, socket.assigns.check.id) do
      {:ok, %Oban.Job{conflict?: true}} ->
        {:noreply, put_flash(socket, :info, "This check is already queued or running.")}

      {:ok, _job} ->
        {:noreply,
         put_flash(socket, :info, "Check queued. Results will appear here when it finishes.")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to rerun this check.")}

      {:error, :disabled} ->
        {:noreply, put_flash(socket, :error, "Enable this check before rerunning it.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not queue the check. Please try again.")}
    end
  end

  @impl true
  def handle_info({:check_result, %CheckResult{check_id: id}}, socket)
      when id == socket.assigns.check.id do
    results = Checks.get_recent_check_results(socket.assigns.check, 48)

    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:latest_analysis, List.first(results))
     |> assign(:last_run, Calendar.strftime(hd(results).inserted_at, "%Y-%m-%d %H:%M:%S"))
     |> assign(:chart_data, ChartData.from_results(results))
     |> assign(:stats, calculate_stats(results))
     |> clear_flash(:info)}
  end

  defp alert_class(:failure), do: "badge badge-error"
  defp alert_class(:anomaly), do: "badge badge-warning"
  defp alert_class(:diff), do: "badge badge-warning"
  defp alert_class(_), do: "badge badge-ghost"

  defp format_result_fields(%CheckResult{success: false, error: error})
       when is_binary(error) and error != "" do
    "Failed: #{error}"
  end

  defp format_result_fields(%CheckResult{result: [row | _]}) when is_map(row) do
    row
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(" ")
  end

  defp format_result_fields(%CheckResult{result: []}), do: "No rows"
  defp format_result_fields(_result), do: "No result"

  defp result_status_class(%CheckResult{is_alert: true, alert_type: alert_type}),
    do: alert_class(alert_type)

  defp result_status_class(%CheckResult{success: true}), do: "badge badge-success"
  defp result_status_class(%CheckResult{success: false}), do: "badge badge-error"

  defp result_status_label(%CheckResult{is_alert: true, alert_type: alert_type}),
    do: String.capitalize(to_string(alert_type))

  defp result_status_label(%CheckResult{success: true}), do: "OK"
  defp result_status_label(%CheckResult{success: false}), do: "Failed"

  # defp analysis(%{analysis: {:ok, nil}} = assigns) do
  #   ~H"""
  #   <div class="alert alert-success mt-3">
  #     <.icon name="hero-check-circle" class="w-6 h-6" />
  #     <div>
  #       <h3 class="font-bold">All good!</h3>
  #       <div class="text-sm">No anomalies or concerning patterns detected in recent results.</div>
  #     </div>
  #   </div>
  #   """
  # end

  # defp analysis(%{analysis: {:alert, %{type: :anomaly, details: details}}} = assigns) do
  #   ~H"""
  #   <div class="alert alert-warning mt-3">
  #     <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
  #     <div>
  #       <h3 class="font-bold">Anomaly Detected</h3>
  #       <div class="text-sm">{details.message}</div>
  #       <div class="grid grid-cols-3 gap-2 mt-2 text-xs">
  #         <div class="stat bg-base-300 rounded p-2">
  #           <div class="stat-title">Current Value</div>
  #           <div class="stat-value text-lg">{format_number(details.current_value)}</div>
  #         </div>
  #         <div class="stat bg-base-300 rounded p-2">
  #           <div class="stat-title">Expected Range</div>
  #           <div class="stat-value text-lg">
  #             {format_number(details.mean - details.std_dev)} - {format_number(
  #               details.mean + details.std_dev
  #             )}
  #           </div>
  #         </div>
  #         <div class="stat bg-base-300 rounded p-2">
  #           <div class="stat-title">Z-Score</div>
  #           <div class="stat-value text-lg">{format_number(details.z_score)}</div>
  #         </div>
  #       </div>
  #     </div>
  #   </div>
  #   """
  # end

  # defp analysis(%{analysis: {:alert, %{type: :diff, details: details}}} = assigns) do
  #   ~H"""
  #   <div class="alert alert-error mt-3">
  #     <.icon name="hero-arrow-trending-up" class="w-6 h-6" />
  #     <div>
  #       <h3 class="font-bold">Significant Change Detected</h3>
  #       <div class="text-sm">{details.message}</div>

  #       <%= cond do %>
  #         <% Map.has_key?(details, :current_value) && Map.has_key?(details, :previous_value) -> %>
  #           <div class="grid grid-cols-3 gap-2 mt-2 text-xs">
  #             <div class="stat bg-base-300 rounded p-2">
  #               <div class="stat-title">Previous Value</div>
  #               <div class="stat-value text-lg">
  #                 {format_number(details.previous_value)}
  #               </div>
  #             </div>
  #             <div class="stat bg-base-300 rounded p-2">
  #               <div class="stat-title">Current Value</div>
  #               <div class="stat-value text-lg">{format_number(details.current_value)}</div>
  #               <%= if Map.has_key?(details, :percent_change) do %>
  #                 <div class={[
  #                   "stat-desc",
  #                   if(details.percent_change > 0, do: "text-success", else: "text-error")
  #                 ]}>
  #                   {(details.current_value > details.previous_value && "+") || "-"}
  #                   {Float.round(abs(details.percent_change) * 100, 1)}%
  #                 </div>
  #               <% end %>
  #             </div>
  #             <div class="stat bg-base-300 rounded p-2">
  #               <div class="stat-title">Threshold</div>
  #               <div class="stat-value text-lg">{Float.round(@threshold * 100, 0)}%</div>
  #             </div>
  #           </div>
  #         <% Map.has_key?(details, :current_status) && Map.has_key?(details, :previous_status) -> %>
  #           <div class="grid grid-cols-2 gap-2 mt-2 text-xs">
  #             <div class="stat bg-base-300 rounded p-2">
  #               <div class="stat-title">Previous Status</div>
  #               <div class="stat-value text-lg">
  #                 <span class={"badge #{details.previous_status && "badge-success" || "badge-error"}"}>
  #                   {(details.previous_status && "Success") || "Failure"}
  #                 </span>
  #               </div>
  #             </div>
  #             <div class="stat bg-base-300 rounded p-2">
  #               <div class="stat-title">Current Status</div>
  #               <div class="stat-value text-lg">
  #                 <span class={"badge #{details.current_status && "badge-success" || "badge-error"}"}>
  #                   {(details.current_status && "Success") || "Failure"}
  #                 </span>
  #               </div>
  #             </div>
  #           </div>
  #         <% Map.has_key?(details, :current_structure) && Map.has_key?(details, :previous_structure) -> %>
  #           <div class="mt-2">
  #             <details class="collapse collapse-arrow bg-base-300">
  #               <summary class="collapse-title text-sm font-medium">
  #                 View Structure Changes
  #               </summary>
  #               <div class="collapse-content text-xs font-mono">
  #                 <div class="grid grid-cols-2 gap-2">
  #                   <div>
  #                     <div class="font-bold mb-1">Previous</div>
  #                     <pre class="bg-base-200 p-2 rounded overflow-auto max-h-40">
  #                       <%= inspect(details.previous_structure, pretty: true) %>
  #                     </pre>
  #                   </div>
  #                   <div>
  #                     <div class="font-bold mb-1">Current</div>
  #                     <pre class="bg-base-200 p-2 rounded overflow-auto max-h-40">
  #                       <%= inspect(details.current_structure, pretty: true) %>
  #                     </pre>
  #                   </div>
  #                 </div>
  #               </div>
  #             </details>
  #           </div>
  #         <% true -> %>
  #           <pre class="text-xs bg-base-300 p-2 rounded mt-2 font-mono overflow-auto max-h-40">
  #             {inspect(details, pretty: true)}
  #           </pre>
  #       <% end %>
  #     </div>
  #   </div>
  #   """
  # end

  # defp analysis(%{analysis: {:error, reason}} = assigns) do
  #   ~H"""
  #   <div class="alert alert-error mt-3">
  #     <.icon name="hero-x-circle" class="w-6 h-6" />
  #     <div>
  #       <h3 class="font-bold">Analysis Error</h3>
  #       <div class="text-sm">Unable to analyze check results: {reason}</div>
  #     </div>
  #   </div>
  #   """
  # end

  # Helper functions for formatting display values
  defp format_number(nil), do: "N/A"
  defp format_number(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 2)
  defp format_number(num), do: to_string(num)

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  # Calculate basic statistics
  defp calculate_stats(results) do
    success_count = Enum.count(results, & &1.success)
    alert_count = Enum.count(results, & &1.is_alert)

    success_rate =
      if length(results) > 0,
        do: trunc(success_count / length(results) * 100),
        else: 0

    alert_rate =
      if length(results) > 0,
        do: trunc(alert_count / length(results) * 100),
        else: 0

    # Extract numeric values for average calculation
    numeric_values =
      results
      |> Enum.map(&ChartData.value/1)
      |> Enum.filter(&is_number/1)

    avg_value =
      if length(numeric_values) > 0,
        do: Enum.sum(numeric_values) / length(numeric_values),
        else: nil

    avg_time =
      if length(results) > 0,
        do: trunc(Enum.sum(Enum.map(results, & &1.time_taken)) / length(results)),
        else: 0

    %{
      success_rate: success_rate,
      alert_rate: alert_rate,
      avg_value: avg_value,
      avg_time: avg_time
    }
  end
end
