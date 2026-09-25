defmodule QueryCanary.Notifications.Chart do
  @moduledoc "A snapshot of the site's Chart.js result history for notification providers."
  alias QueryCanary.Checks.ChartData
  alias QueryCanary.Charts.PNG
  require Logger

  def render(_check, []), do: nil

  def render(check, results) do
    case results |> ChartData.from_results() |> PNG.render() do
      {:ok, png} ->
        %{
          png: png,
          filename: "querycanary-#{check.id}-#{hd(results).id}.png",
          title: "Result History",
          alt_text:
            "#{String.slice(check.name, 0, 150)}: #{length(results)} recent runs ending at " <>
              "#{Calendar.strftime(hd(results).inserted_at, "%Y-%m-%d %H:%M:%S UTC")}. " <>
              "The same result-history chart as the check page; yellow points indicate alerts."
        }

      {:error, reason} ->
        Logger.warning("Could not render notification chart for check #{check.id}: #{reason}")
        nil
    end
  rescue
    # An optional image must never prevent the alert itself from being delivered.
    _ ->
      Logger.warning("Could not render notification chart for check #{check.id}")
      nil
  end
end
