defmodule QueryCanary.Checks.ChartData do
  @moduledoc "The result-history series shared by the check page and notification snapshots."

  def from_results(results) do
    chronological = Enum.reverse(results)
    values = Enum.map(chronological, &value/1)
    numbers = Enum.filter(values, &is_number/1)

    %{
      labels: Enum.map(chronological, &Calendar.strftime(&1.inserted_at, label_format(results))),
      values: values,
      success: Enum.map(chronological, &if(&1.is_alert, do: 0, else: 1)),
      average: if(numbers == [], do: nil, else: Enum.sum(numbers) / length(numbers)),
      alert_threshold: thresholds(List.first(results)),
      alert_type: if(results == [], do: :none, else: hd(results).alert_type)
    }
  end

  def value(%{success: false}), do: nil
  def value(result), do: primary_value(result.result)

  defp primary_value([row | _]) when is_map(row) do
    values = Map.values(row)
    Enum.find(values, &is_number/1) || List.first(values)
  end

  defp primary_value(_), do: nil

  defp thresholds(%{alert_type: :anomaly, analysis_details: details}) when is_map(details) do
    mean = Map.get(details, "mean", Map.get(details, :mean))
    std_dev = Map.get(details, "std_dev", Map.get(details, :std_dev))

    if is_number(mean) and is_number(std_dev) do
      %{upper: mean + std_dev * 3, lower: mean - std_dev * 3}
    else
      %{upper: nil, lower: nil}
    end
  end

  defp thresholds(_), do: %{upper: nil, lower: nil}

  defp label_format([first, second | _]) do
    diff = DateTime.diff(first.inserted_at, second.inserted_at)

    cond do
      diff <= 60 -> "%Y-%m-%d %H:%M"
      diff <= 3600 -> "%Y-%m-%d %H"
      diff <= 86400 -> "%Y-%m-%d"
      true -> "%Y-%m-%d %H:%M:%S"
    end
  end

  defp label_format(_), do: "%Y-%m-%d %H:%M:%S"
end
