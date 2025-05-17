defmodule QueryCanary.CheckResultAnalyzerTest do
  use QueryCanary.DataCase

  alias QueryCanary.CheckResultAnalyzer
  alias QueryCanary.Checks.CheckResult

  describe "analyze_results/2" do
    test "returns ok when no results are provided" do
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results([])
    end

    test "returns ok when only one result is provided" do
      result = build_check_result(true, [%{count: 42}])
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results([result])
    end

    test "detects an anomaly when value is far from the mean" do
      # Create a series of relatively stable results and one outlier
      results =
        [build_check_result(true, [%{count: 100}])] ++
          Enum.map(1..10, fn _ -> build_check_result(true, [%{count: 50}]) end)

      assert {:alert, %{type: :anomaly}} = CheckResultAnalyzer.analyze_results(results)
    end

    test "detects a diff issue when values change significantly" do
      # Create two results with a significant difference
      results = [
        build_check_result(true, [%{count: 100}]),
        build_check_result(true, [%{count: 50}])
      ]

      assert {:alert, %{type: :diff}} = CheckResultAnalyzer.analyze_results(results)
    end

    test "detects status change from success to failure" do
      results = [
        build_check_result(false, []),
        build_check_result(true, [%{count: 50}])
      ]

      assert {:alert, %{type: :diff}} = CheckResultAnalyzer.analyze_results(results)

      # Details should include status change message
      {:alert, %{details: details}} = CheckResultAnalyzer.analyze_results(results)
      assert String.contains?(details.message, "status changed from success to failure")
    end

    test "detects structural changes in result" do
      results = [
        build_check_result(true, [%{count: 50, new_column: "test"}]),
        build_check_result(true, [%{count: 50}])
      ]

      assert {:alert, %{type: :diff}} = CheckResultAnalyzer.analyze_results(results)

      # Details should include structure change message
      {:alert, %{details: details}} = CheckResultAnalyzer.analyze_results(results)
      assert String.contains?(details.message, "Data structure changed")
    end

    test "handles non-numeric results" do
      results = [
        build_check_result(true, [%{status: "error"}]),
        build_check_result(true, [%{status: "ok"}])
      ]

      # Should use structural comparison for non-numeric data
      assert {:alert, %{type: :diff}} = CheckResultAnalyzer.analyze_results(results)

      # Details should describe the change
      {:alert, %{details: details}} = CheckResultAnalyzer.analyze_results(results)
      assert details.current_structure != details.previous_structure
    end

    test "respects diff threshold option" do
      # Create two results with a small difference (20%)
      results = [
        build_check_result(true, [%{count: 120}]),
        build_check_result(true, [%{count: 100}])
      ]

      # With default threshold (25%), no alert should be generated
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results(results)

      # With lower threshold (15%), an alert should be generated
      assert {:alert, %{type: :diff}} =
               CheckResultAnalyzer.analyze_results(results, diff_threshold: 0.15)
    end

    test "respects anomaly threshold option" do
      # Create results with mild outlier (2 std deviations)
      base_value = 100
      std_dev = 10

      # 2 std deviations away
      results =
        [build_check_result(true, [%{count: base_value + 2 * std_dev}])] ++
          Enum.map(1..10, fn _ -> build_check_result(true, [%{count: base_value}]) end)

      # With default threshold (3.0), no alert should be generated
      assert {:ok, nil} = CheckResultAnalyzer.analyze_results(results)

      # With lower threshold (1.5), an alert should be generated
      assert {:alert, %{type: :anomaly}} =
               CheckResultAnalyzer.analyze_results(results, anomaly_threshold: 1.5)
    end
  end

  describe "extract_numeric_values/1" do
    test "extracts numbers from simple count results" do
      results = [
        build_check_result(true, [%{count: 42}]),
        build_check_result(true, [%{count: 100}])
      ]

      assert {:ok, [42, 100]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "extracts numbers from results with different column names" do
      results = [
        build_check_result(true, [%{total: 42}]),
        build_check_result(true, [%{sum: 100}]),
        build_check_result(true, [%{avg: 50}])
      ]

      assert {:ok, values} = CheckResultAnalyzer.extract_numeric_values(results)
      assert Enum.sort(values) == [42, 50, 100]
    end

    test "extracts first numeric value from multi-column results" do
      results = [
        build_check_result(true, [%{count: 42, name: "users"}]),
        build_check_result(true, [%{count: 100, name: "orders"}])
      ]

      assert {:ok, [42, 100]} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "returns error for non-numeric results" do
      results = [
        build_check_result(true, [%{status: "ok"}]),
        build_check_result(true, [%{name: "test"}])
      ]

      assert {:error, :non_numeric} = CheckResultAnalyzer.extract_numeric_values(results)
    end

    test "filters out nil values from failed or empty results" do
      results = [
        build_check_result(true, [%{count: 42}]),
        build_check_result(false, []),
        build_check_result(true, [%{count: 100}])
      ]

      assert {:ok, [42, 100]} = CheckResultAnalyzer.extract_numeric_values(results)
    end
  end

  describe "detect_diff_issues/2" do
    test "identifies significant percentage increases" do
      results = [
        build_check_result(true, [%{count: 100}]),
        build_check_result(true, [%{count: 50}])
      ]

      assert {:alert, details} = CheckResultAnalyzer.detect_diff_issues(results, 0.25)
      assert details.current_value == 100
      assert details.previous_value == 50
      assert details.percent_change > 0.9
    end

    test "identifies significant percentage decreases" do
      results = [
        build_check_result(true, [%{count: 50}]),
        build_check_result(true, [%{count: 100}])
      ]

      assert {:alert, details} = CheckResultAnalyzer.detect_diff_issues(results, 0.25)
      assert details.current_value == 50
      assert details.previous_value == 100
      assert details.percent_change == 0.5
    end

    test "handles zero to non-zero changes" do
      results = [
        build_check_result(true, [%{count: 50}]),
        build_check_result(true, [%{count: 0}])
      ]

      assert {:alert, details} = CheckResultAnalyzer.detect_diff_issues(results, 0.25)
      assert details.message =~ "Value changed from zero"
    end

    test "returns ok for changes below threshold" do
      results = [
        build_check_result(true, [%{count: 105}]),
        build_check_result(true, [%{count: 100}])
      ]

      assert {:ok, nil} = CheckResultAnalyzer.detect_diff_issues(results, 0.25)
    end
  end

  describe "detect_anomaly/2" do
    test "detects outliers in a sequence of values" do
      # 200 is an outlier
      values = [200, 50, 51, 49, 50, 52, 48, 51, 50]
      assert {:alert, details} = CheckResultAnalyzer.detect_anomaly(values, 3.0)
      assert details.current_value == 200
      # Should be about 6 standard deviations from mean
      assert_in_delta details.z_score, 6.0, 0.5
    end

    test "ignores small variations" do
      # All values close to mean
      values = [52, 50, 51, 49, 50, 52, 48, 51, 50]
      assert {:ok, nil} = CheckResultAnalyzer.detect_anomaly(values, 3.0)
    end

    test "handles sequences with zero standard deviation" do
      # All values identical
      values = [50, 50, 50, 50, 50]
      assert {:ok, nil} = CheckResultAnalyzer.detect_anomaly(values, 3.0)
    end

    test "respects the threshold parameter" do
      # Mild outlier
      values = [70, 50, 51, 49, 50, 52, 48, 51, 50]

      # With standard threshold (3.0), no alert
      assert {:ok, nil} = CheckResultAnalyzer.detect_anomaly(values, 3.0)

      # With lower threshold (2.0), generates alert
      assert {:alert, _details} = CheckResultAnalyzer.detect_anomaly(values, 2.0)
    end
  end

  # Helper functions

  defp build_check_result(success, result, opts \\ []) do
    inserted_at = Keyword.get(opts, :inserted_at, DateTime.utc_now())
    error = if success, do: nil, else: Keyword.get(opts, :error, "Test error")

    %CheckResult{
      success: success,
      result: result,
      error: error,
      time_taken: Keyword.get(opts, :time_taken, 42),
      check_id: Keyword.get(opts, :check_id, "check-123"),
      inserted_at: inserted_at
    }
  end
end
