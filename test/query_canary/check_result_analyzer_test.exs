defmodule QueryCanary.CheckResultAnalyzerTest do
  use QueryCanary.DataCase

  alias QueryCanary.CheckResultAnalyzer
  alias QueryCanary.Checks.CheckResult

  describe "extract_numeric_values/1" do
    test "extracts numeric values from check results with map rows" do
      results = [
        %CheckResult{success: true, result: [%{count: 10}]},
        %CheckResult{success: true, result: [%{count: 15}]},
        %CheckResult{success: true, result: [%{count: 20}]}
      ]

      assert {:ok, [10, 15, 20]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "extracts values from rows with different column names" do
      results = [
        %CheckResult{success: true, result: [%{sum: 100}]},
        %CheckResult{success: true, result: [%{avg: 200}]},
        %CheckResult{success: true, result: [%{value: 300}]}
      ]

      assert {:ok, [100, 200, 300]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "extracts first numeric value when no standard column names match" do
      results = [
        %CheckResult{success: true, result: [%{id: 1, metric: 50, name: "test"}]},
        %CheckResult{success: true, result: [%{id: 2, metric: 60, name: "test"}]}
      ]

      assert {:ok, [1, 2]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "filters out non-successful results" do
      results = [
        %CheckResult{success: true, result: [%{count: 10}]},
        %CheckResult{success: false, result: "Error"},
        %CheckResult{success: true, result: [%{count: 20}]}
      ]

      assert {:ok, [10, 20]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "returns error when no numeric values found" do
      results = [
        %CheckResult{success: true, result: [%{name: "test"}]},
        %CheckResult{success: true, result: [%{status: "ok"}]}
      ]

      assert {:error, :non_numeric} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "handles empty results" do
      results = [
        %CheckResult{success: true, result: []},
        %CheckResult{success: true, result: []}
      ]

      assert {:error, :non_numeric} = CheckResultAnalyzer.extract_numeric_values(results)
    end
  end

  describe "detect_diff_issues/2" do
    test "detects status change from success to failure" do
      results = [
        %CheckResult{success: false, result: "Error"},
        %CheckResult{success: true, result: [%{count: 10}]}
      ]

      assert {:alert, %{type: :diff, details: details}} =
               CheckResultAnalyzer.detect_diff_issues(results, 0.25)

      assert details.message =~ "Check status changed from success to failure"
      assert details.previous_status == true
      assert details.current_status == false
    end

    test "detects numeric value changes above threshold" do
      results = [
        %CheckResult{success: true, result: [%{count: 15}]},
        %CheckResult{success: true, result: [%{count: 10}]}
      ]

      assert {:alert, %{type: :diff, details: details}} =
               CheckResultAnalyzer.detect_diff_issues(results, 0.25)

      assert details.message =~ "Value changed by 50.0%"
      assert details.previous_value == 10
      assert details.current_value == 15
      assert_in_delta details.percent_change, 0.5, 0.001
    end

    test "detects string value changes above threshold" do
      results = [
        %CheckResult{success: true, result: [%{keyword: "baz"}]},
        %CheckResult{success: true, result: [%{keyword: "bar"}]}
      ]

      assert {:alert, %{type: :diff, details: details}} =
               CheckResultAnalyzer.detect_diff_issues(results, 0.25)

      assert details.message =~ "Text changed by 66.7%"
      assert details.previous_value == "bar"
      assert details.current_value == "baz"
      assert_in_delta details.percent_change, 0.66, 0.01
    end

    test "no alert when changes are below threshold" do
      results = [
        %CheckResult{success: true, result: [%{count: 11}]},
        %CheckResult{success: true, result: [%{count: 10}]}
      ]

      assert {:ok, nil} = CheckResultAnalyzer.detect_diff_issues(results, 0.25)
    end

    test "detects change from zero to non-zero" do
      results = [
        %CheckResult{success: true, result: [%{count: 10}]},
        %CheckResult{success: true, result: [%{count: 0}]}
      ]

      assert {:alert, %{type: :diff, details: details}} =
               CheckResultAnalyzer.detect_diff_issues(results, 0.25)

      assert details.message =~ "Value changed from zero to 10"
      assert details.previous_value == 0
      assert details.current_value == 10
    end

    test "detects structural changes in results" do
      results = [
        %CheckResult{success: true, result: [%{count: 10, new_field: "test"}]},
        %CheckResult{success: true, result: [%{count: 10}]}
      ]

      assert {:alert, %{type: :diff, details: details}} =
               CheckResultAnalyzer.detect_diff_issues(results, 0.25)

      assert details.message =~ "Data structure changed"
      assert details.current_structure != details.previous_structure
    end
  end

  describe "detect_anomaly/2" do
    test "detects anomalies beyond threshold" do
      values = [300, 100, 102, 98, 103, 97, 101]

      assert {:alert, %{details: details}} = CheckResultAnalyzer.detect_anomaly(values, 3.0)

      assert details.message =~ "Anomalous value detected"
      assert details.current_value == 300
    end

    test "ignores anomalies below threshold" do
      # Values with minor variation
      values = [100, 102, 98, 103, 97, 101, 110]

      assert {:ok, nil} = CheckResultAnalyzer.detect_anomaly(values, 3.0)
    end

    test "handles constant values" do
      values = [10, 10, 10, 10, 10]

      assert {:ok, nil} = CheckResultAnalyzer.detect_anomaly(values, 3.0)
    end
  end

  describe "analyze_results/2" do
    test "returns ok with empty results" do
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results([])
    end

    test "returns ok with single result" do
      result = %CheckResult{success: true, result: [%{count: 10}]}
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results([result])
    end

    test "detects anomaly with sufficient samples" do
      # Create a series with the last value being anomalous
      results =
        Enum.map(1..10, fn i ->
          value = if i == 1, do: 100, else: Enum.random([49, 50, 51])
          %CheckResult{success: true, result: [%{count: value}]}
        end)

      assert {:alert, %{type: :anomaly}} =
               CheckResultAnalyzer.analyze_results(results,
                 min_samples: 5,
                 anomaly_threshold: 3.0
               )
    end

    test "detects diff over anomaly if samples don't meet a min std deviation" do
      # Create a series with the last value being anomalous
      results =
        Enum.map(1..10, fn i ->
          value = if i == 1, do: 100, else: 50
          %CheckResult{success: true, result: [%{count: value}]}
        end)

      assert {:alert, %{type: :diff}} =
               CheckResultAnalyzer.analyze_results(results,
                 min_samples: 5,
                 anomaly_threshold: 3.0
               )
    end

    test "falls back to diff detection with insufficient samples" do
      # Only 2 samples, not enough for anomaly detection
      results = [
        %CheckResult{success: true, result: [%{count: 15}]},
        %CheckResult{success: true, result: [%{count: 10}]}
      ]

      assert {:alert, %{type: :diff}} =
               CheckResultAnalyzer.analyze_results(results, min_samples: 5, diff_threshold: 0.25)
    end

    test "uses structural diff detection for non-numeric data" do
      results = [
        %CheckResult{success: true, result: [%{name: "test2"}]},
        %CheckResult{success: true, result: [%{name: "test", status: "ok"}]}
      ]

      assert {:alert, %{type: :diff}} = CheckResultAnalyzer.analyze_results(results)
    end

    test "respects history window parameter" do
      # Create many results but limit history window
      results =
        Enum.map(1..30, fn i ->
          %CheckResult{success: true, result: [%{count: i}]}
        end)

      # Should only use first 5 results
      assert {:alert, %{type: :diff}} =
               CheckResultAnalyzer.analyze_results(results, history_window: 5)
    end
  end
end
