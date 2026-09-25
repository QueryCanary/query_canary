defmodule QueryCanary.Notifications.Alert do
  @moduledoc "A provider-independent description of a check alert."
  defstruct [:title, :check_name, :server_name, :summary, :occurred_at, :url, :chart, details: []]

  def from_result(check, result) do
    %__MODULE__{
      title: title(result.alert_type),
      check_name: check.name,
      server_name: check.server.name,
      summary: result.analysis_summary || result.error || "This check needs attention.",
      details: details(result),
      occurred_at: result.inserted_at,
      url: QueryCanaryWeb.Endpoint.url() <> "/checks/#{check.id}"
    }
  end

  @doc "Formats the persisted analysis for notification providers, including email."
  def details(%{alert_type: type, analysis_details: analysis} = result) do
    analysis = analysis || %{}

    fields =
      case type do
        :diff ->
          fields(analysis, [
            {:previous_value, "Previous value", &format_value/1},
            {:current_value, "Current value", &format_value/1},
            {:percent_change, "Change", &percent/1},
            {:previous_status, "Previous status", &status/1},
            {:current_status, "Current status", &status/1},
            {:previous_structure, "Previous structure", &structure/1},
            {:current_structure, "Current structure", &structure/1}
          ])

        :anomaly ->
          fields(analysis, [{:current_value, "Current value", &format_value/1}]) ++
            expected_range(analysis) ++
            fields(analysis, [{:z_score, "Z-score", &rounded/1}])

        _ ->
          []
      end

    if is_binary(result.error) and result.error != "",
      do: fields ++ [{"Error", result.error}],
      else: fields
  end

  # Ecto JSON maps have string keys; freshly analyzed results have atom keys.
  # Map.get's default preserves meaningful false, zero, and nil values.
  def detail(details, key, default \\ nil),
    do: Map.get(details || %{}, Atom.to_string(key), Map.get(details || %{}, key, default))

  def format_value(nil), do: "N/A"
  def format_value(value) when is_binary(value), do: value
  def format_value(value) when is_number(value) or is_boolean(value), do: to_string(value)
  def format_value(value), do: inspect(value, limit: 20, printable_limit: 1000)

  defp fields(details, specs) do
    for {key, label, formatter} <- specs,
        Map.has_key?(details, Atom.to_string(key)) or Map.has_key?(details, key),
        do: {label, formatter.(detail(details, key))}
  end

  defp expected_range(details) do
    mean = detail(details, :mean)
    std_dev = detail(details, :std_dev)

    if is_number(mean) and is_number(std_dev) do
      [{"Expected range", "#{rounded(mean - std_dev)} – #{rounded(mean + std_dev)}"}]
    else
      []
    end
  end

  defp percent(value) when is_number(value), do: "#{Float.round(value * 100.0, 1)}%"
  defp percent(value), do: format_value(value)
  defp rounded(value) when is_float(value), do: format_value(Float.round(value, 2))
  defp rounded(value), do: format_value(value)
  defp status(true), do: "Succeeded"
  defp status(false), do: "Failed"
  defp status(value), do: format_value(value)

  defp structure(value) when is_map(value) do
    [
      if(is_number(detail(value, :row_count)), do: "#{detail(value, :row_count)} rows"),
      if(is_list(detail(value, :columns)),
        do: "Columns: " <> Enum.map_join(detail(value, :columns), ", ", &format_value/1)
      ),
      detail(value, :type)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp structure(value), do: format_value(value)

  defp title(:anomaly), do: "Anomaly Detected"
  defp title(:diff), do: "Significant Change Detected"
  defp title(:failure), do: "Check Failed"
  defp title(_), do: "Alert"
end
