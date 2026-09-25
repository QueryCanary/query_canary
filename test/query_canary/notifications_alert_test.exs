defmodule QueryCanary.Notifications.AlertTest do
  use ExUnit.Case, async: true
  alias QueryCanary.Checks.CheckResult
  alias QueryCanary.Notifications.Alert

  test "numeric diffs show the saved values and fractional change as a percentage" do
    result = %CheckResult{
      alert_type: :diff,
      analysis_details: %{
        "previous_value" => 200,
        "current_value" => 125,
        "percent_change" => 0.375
      }
    }

    assert Alert.details(result) == [
             {"Previous value", "200"},
             {"Current value", "125"},
             {"Change", "37.5%"}
           ]
  end

  test "false, zero, nil, text and fresh atom keys are preserved" do
    for {previous, current, expected} <- [
          {true, false, "false"},
          {10, 0, "0"},
          {0, nil, "N/A"},
          {"old", "<new>", "<new>"}
        ] do
      fields =
        Alert.details(%CheckResult{
          alert_type: :diff,
          analysis_details: %{previous_value: previous, current_value: current}
        })

      assert {"Current value", expected} in fields
      refute Enum.any?(fields, fn {label, _} -> label == "Change" end)
    end
  end

  test "anomalies contain the same expected range and z-score as the alert panel" do
    assert Alert.details(%CheckResult{
             alert_type: :anomaly,
             analysis_details: %{
               "current_value" => 250,
               "mean" => 100.0,
               "std_dev" => 5.0,
               "z_score" => 30.0
             }
           }) == [
             {"Current value", "250"},
             {"Expected range", "95.0 – 105.0"},
             {"Z-score", "30.0"}
           ]
  end

  test "status changes, structural changes and failures show applicable details" do
    assert Alert.details(%CheckResult{
             alert_type: :diff,
             analysis_details: %{
               "previous_status" => true,
               "current_status" => false
             },
             error: "Database unavailable"
           }) == [
             {"Previous status", "Succeeded"},
             {"Current status", "Failed"},
             {"Error", "Database unavailable"}
           ]

    fields =
      Alert.details(%CheckResult{
        alert_type: :diff,
        analysis_details: %{
          "previous_structure" => %{"row_count" => 0},
          "current_structure" => %{"row_count" => 2, "columns" => ["name", "status"]}
        }
      })

    assert {"Previous structure", "0 rows"} in fields
    assert {"Current structure", "2 rows\nColumns: name, status"} in fields

    assert Alert.details(%CheckResult{alert_type: :failure, error: "Query timed out"}) == [
             {"Error", "Query timed out"}
           ]

    assert Alert.details(%CheckResult{}) == []
  end
end
