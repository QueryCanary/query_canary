defmodule QueryCanaryWeb.CheckLive.Show do
  use QueryCanaryWeb, :live_view

  alias Crontab.CronExpression
  alias QueryCanary.Checks
  alias QueryCanary.Checks.CheckResult

  import QueryCanaryWeb.Components.CheckAnalysis

  on_mount QueryCanaryWeb.CheckAuth

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

      <%!-- <.analysis analysis={@analysis} threshold={@threshold} /> --%>
      <!-- SQL Query Viewer -->
      <div class="card bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">SQL Query</h2>
          <pre class="bg-base-300 text-sm p-4 rounded-lg overflow-x-auto font-mono">{@check.query}</pre>
        </div>
      </div>

      <.check_analysis result={@latest_analysis} />

      <div class="card bg-base-200">
        <div class="card-body space-y-4">
          <h2 class="card-title">Result History</h2>

          <%= if length(@results) > 0 do %>
            <canvas
              id="resultChart"
              class="w-full h-64"
              phx-hook="CheckChart"
              data-labels={Jason.encode!(@chart_data.labels)}
              data-values={Jason.encode!(@chart_data.values)}
              data-success={Jason.encode!(@chart_data.success)}
              data-average={Jason.encode!(@chart_data.average)}
              data-alert-threshold={Jason.encode!(@chart_data.alert_threshold)}
              data-alert-type={@chart_data.alert_type}
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
                {Enum.map(hd(result.result), fn {k, v} -> "#{k}=#{v}" end) |> Enum.join(" ")}
              </:col>
              <:col :let={result} label="Alert Type">
                <%= if result.is_alert do %>
                  <span class={alert_class(result.alert_type)}>
                    {String.capitalize(to_string(result.alert_type))}
                  </span>
                <% else %>
                  <span class="badge badge-success" title={result.error}>OK</span>
                <% end %>
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
    # check = Checks.get_check!(socket.assigns.current_scope, id)
    recent_results = Checks.get_recent_check_results(check, 10)

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
     |> assign(:page_title, "Check Details")
     |> assign(:check, check)
     |> assign(:can_edit?, can_perform?(:edit, socket.assigns.current_scope, check))
     |> assign(:latest_analysis, latest_result)
     |> assign(:results, recent_results)
     |> assign(:last_run, last_run)
     |> assign(:next_run, next_run)
     |> assign(:chart_data, prepare_chart_data(recent_results))
     |> assign(:stats, calculate_stats(recent_results))}
  end

  defp alert_class(:failure), do: "badge badge-error"
  defp alert_class(:anomaly), do: "badge badge-warning"
  defp alert_class(:diff), do: "badge badge-warning"
  defp alert_class(_), do: "badge badge-ghost"

  defp can_perform?(:edit, nil, _), do: false

  defp can_perform?(
         :edit,
         %QueryCanary.Accounts.Scope{} = scope,
         %QueryCanary.Checks.Check{} = check
       ) do
    check.user_id == scope.user.id
  end

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

  defp extract_primary_value(nil), do: nil
  defp extract_primary_value([]), do: nil

  defp extract_primary_value([row | _]) when is_map(row) do
    # Try to get the first numeric value
    Map.values(row)
    |> Enum.find(fn v -> is_number(v) end)
    |> case do
      nil -> Map.values(row) |> List.first()
      val -> val
    end
  end

  defp extract_primary_value(other), do: other

  # Prepare chart data from check results
  defp prepare_chart_data([]), do: %{}

  defp prepare_chart_data(results) do
    # Reverse results to get chronological order (oldest to newest)
    chronological_results = Enum.reverse(results)
    latest_result = hd(results)

    labels =
      Enum.map(chronological_results, fn result ->
        # TODO: Be smarter, only show format based on specificity of cron schedule
        Calendar.strftime(result.inserted_at, "%Y-%m-%d")
      end)

    values =
      Enum.map(chronological_results, fn result ->
        extract_primary_value(result.result)
      end)

    success =
      Enum.map(chronological_results, fn result ->
        if result.is_alert, do: 0, else: 1
      end)

    # Calculate average for reference line
    average =
      case Enum.filter(values, &is_number/1) do
        [] -> nil
        nums -> Enum.sum(nums) / length(nums)
      end

    # Set alert thresholds for anomaly detection
    alert_threshold =
      case latest_result do
        %CheckResult{alert_type: :anomaly, analysis_details: details} ->
          %{
            upper: details["mean"] + details["std_dev"] * 3,
            lower: details["mean"] - details["std_dev"] * 3
          }

        _ ->
          %{upper: nil, lower: nil}
      end

    %{
      labels: labels,
      values: values,
      success: success,
      average: average,
      alert_threshold: alert_threshold,
      alert_type: latest_result.alert_type
    }
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
      |> Enum.map(fn r -> extract_primary_value(r.result) end)
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
