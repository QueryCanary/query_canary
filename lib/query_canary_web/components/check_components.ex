defmodule QueryCanaryWeb.Components.CheckAnalysis do
  use Phoenix.Component

  import QueryCanaryWeb.CoreComponents

  attr :result, CheckResult

  def check_analysis(%{result: %{is_alert: false}} = assigns) do
    ~H"""
    <div class="alert alert-info">
      <span>No analysis data available yet.</span>
    </div>
    """
  end

  def check_analysis(assigns) do
    ~H"""
    <div class={[
      "alert mt-4",
      @result.is_alert && "alert-warning",
      !@result.is_alert && "alert-success"
    ]}>
      <div class="flex items-start">
        <div class="mr-2">
          <%= if @result.is_alert do %>
            <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
          <% else %>
            <.icon name="hero-check-circle" class="h-6 w-6" />
          <% end %>
        </div>
        <div>
          <h3 class="font-semibold">
            {analysis_title(@result.alert_type)} on {format_date(@result.inserted_at)}
          </h3>
          <p class="text-sm mt-1">{@result.analysis_summary}</p>

          <%= if @result.is_alert && @result.analysis_details do %>
            <div class="mt-2">
              <%= if @result.alert_type == :diff do %>
                <div class="grid grid-cols-2 gap-4 mt-2">
                  <div class="bg-base-200 p-2 rounded">
                    <div class="text-xs font-semibold mb-1">Previous:</div>
                    <div class="font-mono text-sm">
                      {format_value(@result.analysis_details["previous_value"])}
                    </div>
                  </div>
                  <div class="bg-base-200 p-2 rounded">
                    <div class="text-xs font-semibold mb-1">Current:</div>
                    <div class="font-mono text-sm">
                      {format_value(@result.analysis_details["current_value"])}
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @result.alert_type == :anomaly do %>
                <div>
                  <div class="grid grid-cols-3 gap-2 mt-2 text-xs">
                    <div class="stat bg-base-300 rounded p-2">
                      <div class="stat-title">Current Value</div>
                      <div class="stat-value text-lg">
                        {format_number(@result.analysis_details["current_value"])}
                      </div>
                    </div>
                    <div class="stat bg-base-300 rounded p-2">
                      <div class="stat-title">Expected Range</div>
                      <div class="stat-value text-lg">
                        {format_number(
                          @result.analysis_details["mean"] - @result.analysis_details["std_dev"]
                        )} - {format_number(
                          @result.analysis_details["mean"] + @result.analysis_details["std_dev"]
                        )}
                      </div>
                    </div>
                    <div class="stat bg-base-300 rounded p-2">
                      <div class="stat-title">Z-Score</div>
                      <div class="stat-value text-lg">
                        {format_number(@result.analysis_details["z_score"])}
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp analysis_title(type) do
    case type do
      :anomaly -> "Anomaly Detected"
      :diff -> "Significant Change Detected"
      _ -> to_string(type)
    end
  end

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_date(_), do: "N/A"

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: "#{value}"
  defp format_value(value), do: inspect(value)

  defp format_number(nil), do: "N/A"
  defp format_number(num) when is_float(num), do: :erlang.float_to_binary(num, decimals: 2)
  defp format_number(num), do: to_string(num)
end
