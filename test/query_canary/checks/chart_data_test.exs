defmodule QueryCanary.Checks.ChartDataTest do
  use ExUnit.Case, async: true
  alias QueryCanary.Checks.{ChartData, CheckResult}

  test "history is chronological and preserves zero, gaps, site labels and alert markers" do
    data =
      ChartData.from_results([
        result(3, 200, is_alert: true, alert_type: :diff),
        result(2, 500, success: false),
        result(1, 0)
      ])

    assert data.values == [0, nil, 200]
    assert data.labels == ["2026-09-25 12:01", "2026-09-25 12:02", "2026-09-25 12:03"]
    assert data.success == [1, 1, 0]
    assert data.average == 100
    assert data.alert_threshold == %{upper: nil, lower: nil}
  end

  test "anomaly reference lines use the site's displayed average and three-sigma limits" do
    for details <- [%{"mean" => 100, "std_dev" => 5}, %{mean: 100, std_dev: 5}] do
      data =
        ChartData.from_results([
          result(3, 250, alert_type: :anomaly, analysis_details: details),
          result(2, 100),
          result(1, 100)
        ])

      assert data.average == 150
      assert data.alert_threshold == %{upper: 115, lower: 85}
      assert data.alert_type == :anomaly
    end
  end

  test "empty and nonnumeric results match the site without inventing a row-count series" do
    assert ChartData.from_results([]).values == []
    assert ChartData.from_results([result(1, "changed")]).values == ["changed"]
    assert ChartData.from_results([result(1, false)]).values == [false]

    assert ChartData.from_results([result(1, 10, alert_type: :anomaly)]).alert_threshold == %{
             upper: nil,
             lower: nil
           }
  end

  defp result(id, value, attrs \\ []) do
    struct!(
      %CheckResult{
        id: id,
        result: [%{"value" => value}],
        success: true,
        inserted_at: DateTime.add(~U[2026-09-25 12:00:00Z], id * 60)
      },
      attrs
    )
  end
end
