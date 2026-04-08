defmodule QueryCanary.Jobs.MetricBackfillEnqueuer do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias QueryCanary.Metrics
  require Logger

  @runner_spacing_seconds 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"metric_id" => id, "from" => from_iso, "to" => to_iso}}) do
    metric = Metrics.get_metric!(id)
    tz = metric.timezone || "Etc/UTC"

    {:ok, from, 0} = DateTime.from_iso8601(from_iso)
    {:ok, to, 0} = DateTime.from_iso8601(to_iso)

    windows = Metrics.windows_for_range(metric.granularity, from, to, tz)

    Logger.info("MetricBackfillEnqueuer metric=#{metric.id} windows=#{length(windows)}")

    Metrics.delete_metric_results_for_windows(metric.id, windows)

    windows
    |> Enum.with_index()
    |> Stream.map(fn {{f, t}, index} ->
      args = %{
        "metric_id" => metric.id,
        "from" => DateTime.to_iso8601(f),
        "to" => DateTime.to_iso8601(t)
      }

      opts = [
        queue: :metric_backfill,
        schedule_in: index * @runner_spacing_seconds
      ]

      QueryCanary.Jobs.MetricRunner.new(args, opts)
    end)
    |> Enum.each(&Oban.insert/1)

    :ok
  end
end
