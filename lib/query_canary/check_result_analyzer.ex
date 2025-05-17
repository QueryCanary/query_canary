defmodule QueryCanary.CheckResultAnalyzer do
  @moduledoc """
  Detects anomalies and data integrity issues in check results.

  This module analyzes sequences of check results and determines if there are
  issues that should be reported to the user. It supports two main detection methods:

  1. Diff Detection: Compares the latest result with previous results to detect changes
  2. Time Series Analysis: Detects anomalies in numerical sequences using statistical methods
  """

  alias QueryCanary.Checks.CheckResult

  @doc """
  Analyzes a series of check results to determine if there's a reportable issue.

  ## Parameters
    * results - List of check results, ordered by recency (newest first)
    * opts - Options for detection sensitivity and thresholds

  ## Options
    * :diff_threshold - Percentage change threshold for diff alerts (default: 0.25 or 25%)
    * :anomaly_threshold - Z-score threshold for anomaly detection (default: 3.0)
    * :min_samples - Minimum number of samples needed for time series analysis (default: 5)
    * :history_window - Number of recent results to use for analysis (default: 20)

  ## Returns
    * {:ok, nil} - No issues detected
    * {:alert, %{type: :diff, details: details}} - Diff-based alert with details
    * {:alert, %{type: :anomaly, details: details}} - Anomaly-based alert with details
    * {:error, reason} - Error during analysis
  """
  def analyze_results(results, opts \\ [])

  def analyze_results([], _opts), do: {:ok, nil}

  def analyze_results([_single_result], _opts), do: {:ok, nil}

  def analyze_results(results, opts) do
    # Extract configuration options with defaults
    diff_threshold = Keyword.get(opts, :diff_threshold, 0.25)
    anomaly_threshold = Keyword.get(opts, :anomaly_threshold, 3.0)
    min_samples = Keyword.get(opts, :min_samples, 5)
    history_window = Keyword.get(opts, :history_window, 20)

    # Take only the most recent results for analysis
    recent_results = Enum.take(results, history_window)

    # Extract values for analysis if possible
    case extract_numeric_values(recent_results) do
      {:ok, values} when length(values) >= min_samples ->
        # We have enough numeric values for time series analysis
        case detect_anomaly(values, anomaly_threshold) do
          {:alert, details} ->
            # Anomaly detected in time series
            {:alert, %{type: :anomaly, details: details}}

          {:ok, nil} ->
            # No anomaly detected, try diff analysis
            detect_diff_issues(recent_results, diff_threshold)
        end

      {:ok, values} when length(values) > 1 ->
        # Not enough samples for time series, but can do diff analysis
        detect_diff_issues(recent_results, diff_threshold)

      {:ok, _} ->
        # Only one result, nothing to compare
        {:ok, nil}

      {:error, :non_numeric} ->
        # Data is not numeric, use struct diff detection only
        detect_structural_changes(recent_results)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extracts numeric values from a series of check results for analysis.

  ## Returns
    * {:ok, [numeric_values]} - Successfully extracted numeric values
    * {:error, :non_numeric} - Results don't contain consistent numeric values
  """
  def extract_numeric_values(results) do
    values =
      Enum.map(results, fn result ->
        extract_numeric_value(result)
      end)

    # Filter out any non-numeric results
    numeric_values = Enum.filter(values, &is_number/1)

    if length(numeric_values) > 0 do
      {:ok, numeric_values}
    else
      {:error, :non_numeric}
    end
  end

  # Extract numeric values from a result
  defp extract_numeric_value(%CheckResult{} = result) do
    cond do
      # Successful result with rows
      result.success && is_list(result.result) && length(result.result) > 0 ->
        row = List.first(result.result)
        extract_number_from_row(row)

      # Failed result
      !result.success ->
        nil

      # Empty result
      true ->
        nil
    end
  end

  # Extract a number from a row (map) if possible
  defp extract_number_from_row(row) when is_map(row) do
    # Try common patterns for numeric result columns
    # First try exact matches for common aggregate names
    direct_matches = ["count", "sum", "avg", "min", "max", "value"]

    # Look for exact column name matches
    direct_value =
      Enum.find_value(direct_matches, fn key ->
        Map.get(row, String.to_atom(key))
      end)

    if direct_value && is_number(direct_value) do
      direct_value
    else
      # If no direct match, take the first numeric value
      row
      |> Map.values()
      |> Enum.find(&is_number/1)
    end
  end

  defp extract_number_from_row(value) when is_number(value), do: value
  defp extract_number_from_row(_), do: nil

  @doc """
  Detects significant changes between consecutive check results.

  ## Parameters
    * results - List of check results, ordered by recency (newest first)
    * threshold - The percentage change threshold to trigger an alert

  ## Returns
    * {:alert, details} - Alert with information about the change
    * {:ok, nil} - No significant changes detected
  """
  def detect_diff_issues(results, threshold) do
    case results do
      [latest, previous | _rest] ->
        # Compare the latest result with the previous result
        diff_analysis(latest, previous, threshold)

      _ ->
        {:ok, nil}
    end
  end

  # Analyze differences between two consecutive results
  defp diff_analysis(latest, previous, threshold) do
    # First check for status change (success -> failure or vice versa)
    if latest.success != previous.success do
      {:alert,
       %{
         type: :diff,
         details: %{
           message:
             "Check status changed from #{status_text(previous.success)} to #{status_text(latest.success)}",
           previous_status: previous.success,
           current_status: latest.success
         }
       }}
    else
      # If both successful, check for data changes
      if latest.success do
        case {extract_numeric_value(latest), extract_numeric_value(previous)} do
          {latest_val, previous_val} when is_number(latest_val) and is_number(previous_val) ->
            # Calculate percentage change
            if previous_val != 0 do
              pct_change = abs((latest_val - previous_val) / previous_val)

              if pct_change >= threshold do
                {:alert,
                 %{
                   type: :diff,
                   details: %{
                     message:
                       "Value changed by #{Float.round(pct_change * 100, 1)}% (threshold: #{Float.round(threshold * 100, 1)}%)",
                     previous_value: previous_val,
                     current_value: latest_val,
                     percent_change: pct_change
                   }
                 }}
              else
                {:ok, nil}
              end
            else
              # Previous value was zero, so any change is infinite % change
              if latest_val != 0 do
                {:alert,
                 %{
                   type: :diff,
                   details: %{
                     message: "Value changed from zero to #{latest_val}",
                     previous_value: previous_val,
                     current_value: latest_val
                   }
                 }}
              else
                {:ok, nil}
              end
            end

          _ ->
            # Try structural comparison for non-numeric data
            detect_structural_changes([latest, previous])
        end
      else
        # Both failed, nothing to compare
        {:ok, nil}
      end
    end
  end

  # Compare structures of two results
  defp detect_structural_changes(results) do
    case results do
      [latest, previous | _rest] ->
        # Compare result structures
        latest_structure = get_result_structure(latest)
        previous_structure = get_result_structure(previous)

        if latest_structure != previous_structure do
          {:alert,
           %{
             type: :diff,
             details: %{
               message: "Data structure changed between runs",
               previous_structure: previous_structure,
               current_structure: latest_structure
             }
           }}
        else
          {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  @doc """
  Detects anomalies using statistical analysis of time series data.

  ## Parameters
    * values - List of numeric values, newest first
    * threshold - Z-score threshold to consider a value anomalous

  ## Returns
    * {:alert, details} - Alert with information about the anomaly
    * {:ok, nil} - No anomalies detected
  """
  def detect_anomaly(values, threshold) do
    # Reverse values to put them in chronological order for analysis
    values_chronological = Enum.reverse(values)

    # Calculate mean and standard deviation
    mean = mean(values_chronological)
    stdev = standard_deviation(values_chronological, mean)

    # No meaningful deviation if standard deviation is too small
    if stdev < 1.0e-10 || is_nil(stdev) do
      {:ok, nil}
    else
      # Get the most recent value (last in chronological)
      latest_value = List.last(values_chronological)

      # Calculate z-score (how many standard deviations from mean)
      z_score = (latest_value - mean) / stdev

      if abs(z_score) >= threshold do
        {:alert,
         %{
           type: :anomaly,
           details: %{
             message:
               "Anomalous value detected (#{Float.round(abs(z_score), 2)} standard deviations from mean)",
             current_value: latest_value,
             mean: mean,
             std_dev: stdev,
             z_score: z_score
           }
         }}
      else
        {:ok, nil}
      end
    end
  end

  # Basic statistics functions

  # Calculate mean of a list of numbers
  defp mean(values) do
    sum = Enum.sum(values)
    sum / length(values)
  end

  # Calculate standard deviation
  defp standard_deviation(values, mean) do
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  # Helper function for status text
  defp status_text(true), do: "success"
  defp status_text(false), do: "failure"

  # Get a simplified structure representation of a result
  defp get_result_structure(%CheckResult{result: result}) when is_list(result) do
    if length(result) > 0 do
      row = List.first(result)

      if is_map(row) do
        %{
          row_count: length(result),
          columns: Map.keys(row) |> Enum.sort()
        }
      else
        %{
          row_count: length(result),
          type: "non-map"
        }
      end
    else
      %{row_count: 0}
    end
  end

  defp get_result_structure(%CheckResult{result: result}) do
    %{type: inspect(result) |> String.slice(0..20)}
  end
end
