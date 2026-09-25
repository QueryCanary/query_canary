defmodule QueryCanary.Notifications.ChartTest do
  use ExUnit.Case, async: true
  alias QueryCanary.Checks.{Check, CheckResult, ChartData}
  alias QueryCanary.Notifications.Chart
  alias QueryCanary.Charts.PNG

  test "notification image is the same Chart.js PNG generated from the shared site data" do
    results = [
      result(3, 250, alert_type: :anomaly, analysis_details: %{"mean" => 100, "std_dev" => 5}),
      result(2, 100),
      result(1, 95)
    ]

    chart = Chart.render(%Check{id: 1, name: "Orders"}, results)
    assert {:ok, expected_png} = results |> ChartData.from_results() |> PNG.render()
    assert chart.png == expected_png
    assert <<_::binary-size(16), 1940::32, 580::32, _::binary>> = chart.png
    assert chart.filename == "querycanary-1-3.png"
    assert chart.title == "Result History"
    assert chart.alt_text =~ "3 recent runs"
  end

  test "single zero values and failures still render; empty history has no image" do
    check = %Check{id: 1, name: "Count"}

    for result <- [result(1, 0), result(1, nil, success: false)] do
      assert %{png: <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>} =
               Chart.render(check, [result])
    end

    assert Chart.render(check, []) == nil
  end

  test "a missing renderer or invalid payload returns a safe error" do
    assert {:error, :renderer_unavailable} = PNG.render(%{}, executable: nil)
    assert {:error, :renderer_unavailable} = PNG.render(%{}, script: "/nonexistent/render.mjs")
    assert {:error, :render_failed} = PNG.render(%{labels: ["one"], values: []})
  end

  test "renderer timeout is bounded and raw subprocess errors are not returned" do
    path =
      Path.join(
        System.tmp_dir!(),
        "querycanary-renderer-#{System.unique_integer([:positive])}.js"
      )

    on_exit(fn -> File.rm(path) end)

    File.write!(
      path,
      "process.stdin.resume(); process.stdin.on('end', () => process.exit(1)); setInterval(() => {}, 1000);"
    )

    assert {:error, :timeout} = PNG.render(%{}, script: path, timeout: 50)
    File.write!(path, "process.stdout.write('secret-query-data'); process.exit(1);")
    assert {:error, :render_failed} = PNG.render(%{}, script: path)
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
