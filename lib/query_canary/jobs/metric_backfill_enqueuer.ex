defmodule QueryCanary.Jobs.MetricBackfillEnqueuer do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias QueryCanary.Metrics
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"metric_id" => id, "from" => from_iso, "to" => to_iso}}) do
    metric = Metrics.get_metric!(id)
    tz = metric.timezone || "Etc/UTC"

    {:ok, from, 0} = DateTime.from_iso8601(from_iso)
    {:ok, to, 0} = DateTime.from_iso8601(to_iso)

    windows = Metrics.windows_for_range(metric.granularity, from, to, tz)

    Logger.info("MetricBackfillEnqueuer metric=#{metric.id} windows=#{length(windows)}")
    dbg("MetricBackfillEnqueuer metric=#{metric.id} windows=#{length(windows)}")

    windows
    |> Stream.map(fn {f, t} ->
      %{
        "metric_id" => metric.id,
        "from" => DateTime.to_iso8601(f),
        "to" => DateTime.to_iso8601(t)
      }
      |> QueryCanary.Jobs.MetricRunner.new()
    end)
    |> Enum.each(&Oban.insert/1)

    :ok
  end
end
