defmodule QueryCanary.CheckResultAnalyzerRealExamplesTest do
  use QueryCanary.DataCase

  alias QueryCanary.CheckResultAnalyzer
  alias QueryCanary.Checks.CheckResult

  describe "extract_numeric_values/1" do
    test "doesn't use diff detection on long series of results" do
      series = [
        429,
        292,
        312,
        366,
        333,
        394,
        269,
        276,
        359,
        329,
        340,
        380,
        302,
        1274,
        279,
        298,
        347,
        359,
        333,
        303,
        384,
        342,
        362,
        348,
        312,
        326,
        314,
        346,
        347,
        284,
        332,
        378,
        387,
        348,
        374,
        476,
        464,
        376,
        414,
        362,
        345,
        373
      ]

      results =
        Enum.map(series, fn i ->
          %CheckResult{success: true, result: [%{count: i}]}
        end)

      assert {:ok, nil} =
               CheckResultAnalyzer.analyze_results(results,
                 min_samples: 5,
                 anomaly_threshold: 3.0
               )
    end

    test "anomaly checks aren't too sensitive" do
      series = [28, 27, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26]

      results =
        Enum.map(series, fn i ->
          %CheckResult{success: true, result: [%{count: i}]}
        end)

      assert {:ok, nil} =
               CheckResultAnalyzer.analyze_results(results,
                 min_samples: 5,
                 anomaly_threshold: 3.0
               )
    end
  end
end
