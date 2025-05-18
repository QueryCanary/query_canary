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
            {:alert, %{type: :anomaly, details: details.details}}

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
  defp extract_numeric_value(%CheckResult{result: [first | _rest]}) do
    # TODO: We don't care about result.success here
    extract_number_from_row(first)
  end

  defp extract_numeric_value(_), do: nil

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
        case detect_structural_changes([latest, previous]) do
          {:ok, nil} ->
            # Extract primary values from results (could be numbers or strings)
            latest_val = extract_primary_value(latest)
            previous_val = extract_primary_value(previous)

            cond do
              # Handle numeric comparisons
              is_number(latest_val) and is_number(previous_val) ->
                compare_numeric_values(latest_val, previous_val, threshold)

              # Handle string comparisons
              is_binary(latest_val) and is_binary(previous_val) ->
                compare_string_values(latest_val, previous_val, threshold)

              # Handle list comparisons (basic length check)
              is_list(latest_val) and is_list(previous_val) ->
                compare_list_values(latest_val, previous_val, threshold)

              # Handle boolean changes
              is_boolean(latest_val) and is_boolean(previous_val) and latest_val != previous_val ->
                {:alert,
                 %{
                   type: :diff,
                   details: %{
                     message: "Boolean value changed from #{previous_val} to #{latest_val}",
                     previous_value: previous_val,
                     current_value: latest_val
                   }
                 }}

              # Values are of different types
              latest_val != nil and previous_val != nil ->
                {:alert,
                 %{
                   type: :diff,
                   details: %{
                     message:
                       "Value type changed from #{inspect(previous_val)} to #{inspect(latest_val)}",
                     previous_value: previous_val,
                     current_value: latest_val
                   }
                 }}

              # No meaningful comparison possible
              true ->
                {:ok, nil}
            end

          other ->
            other
        end
      else
        # Both failed, nothing to compare
        {:ok, nil}
      end
    end
  end

  # Compare numeric values with threshold
  defp compare_numeric_values(latest_val, previous_val, threshold) do
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
  end

  # Compare string values using string similarity
  defp compare_string_values(latest_val, previous_val, threshold) do
    if latest_val != previous_val do
      # Calculate string similarity (Levenshtein distance relative to string length)
      distance = String.myers_difference(previous_val, latest_val) |> calc_levenshtein_distance()
      max_length = max(String.length(previous_val), String.length(latest_val))

      # Convert to a similarity score
      similarity = if max_length > 0, do: 1 - distance / max_length, else: 1.0
      change_percent = 1 - similarity

      if change_percent >= threshold do
        {:alert,
         %{
           type: :diff,
           details: %{
             message: "Text changed by #{Float.round(change_percent * 100, 1)}%",
             previous_value: previous_val,
             current_value: latest_val,
             percent_change: change_percent
           }
         }}
      else
        {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  # Compare lists (by length and content)
  defp compare_list_values(latest_list, previous_list, threshold) do
    prev_len = length(previous_list)
    curr_len = length(latest_list)

    if prev_len > 0 do
      # Calculate change in list length
      length_change = abs(curr_len - prev_len) / prev_len

      if length_change >= threshold do
        {:alert,
         %{
           type: :diff,
           details: %{
             message: "List length changed by #{Float.round(length_change * 100, 1)}%",
             previous_value: prev_len,
             current_value: curr_len,
             percent_change: length_change
           }
         }}
      else
        # Lists are similar in length, check content similarity
        # Advanced content analysis would go here
        {:ok, nil}
      end
    else
      # Previous list was empty
      if curr_len > 0 do
        {:alert,
         %{
           type: :diff,
           details: %{
             message: "List changed from empty to #{curr_len} items",
             previous_value: prev_len,
             current_value: curr_len
           }
         }}
      else
        {:ok, nil}
      end
    end
  end

  # Extract a single primary value from a CheckResult for comparison
  defp extract_primary_value(%CheckResult{result: [first | _rest]}) when is_map(first) do
    # First try numeric extraction
    numeric_val = extract_number_from_row(first)

    if is_number(numeric_val) do
      numeric_val
    else
      # If not numeric, try string values from common column names
      string_columns = ["name", "status", "message", "value", "text", "description"]

      # Fall back to first string value
      # Last resort - return the whole map
      Enum.find_value(string_columns, fn col ->
        val = Map.get(first, String.to_atom(col)) || Map.get(first, col)
        if is_binary(val), do: val, else: nil
      end) ||
        Enum.find_value(Map.values(first), fn val -> if is_binary(val), do: val, else: nil end) ||
        first
    end
  end

  defp extract_primary_value(%CheckResult{result: result}) when is_list(result), do: result
  defp extract_primary_value(%CheckResult{result: result}), do: result

  # Calculate Levenshtein distance from Myers difference
  defp calc_levenshtein_distance(myers_diff) do
    Enum.reduce(myers_diff, 0, fn
      {:eq, _str}, acc -> acc
      {:ins, str}, acc -> acc + String.length(str)
      {:del, str}, acc -> acc + String.length(str)
    end)
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
    # Get the most recent value (first in the list, as values are newest-first)
    latest_value = List.first(values)

    # Use the older values (excluding the latest) to establish the baseline
    historical_values = Enum.slice(values, 1..-1//1)

    # Need at least some historical values to compare against
    if length(historical_values) == 0 do
      {:ok, :not_enough_values}
    else
      # Calculate baseline statistics from historical values only
      mean = mean(historical_values)
      stdev = standard_deviation(historical_values, mean)

      # No meaningful deviation if standard deviation is too small
      cond do
        stdev < 1.0e-10 ->
          {:ok, nil}

        true ->
          # Calculate z-score (how many standard deviations from mean)
          z_score = (latest_value - mean) / stdev

          if abs(z_score) >= threshold do
            {:alert,
             %{
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
