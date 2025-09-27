defmodule QueryCanary.Jobs.MetricScheduler do
  use Oban.Worker, queue: :default

  require Logger

  alias QueryCanary.Metrics

  @impl Oban.Worker
  def perform(_) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Logger.info("Metrics cron tick at #{now}")

    metrics = Metrics.list_metrics()

    Enum.each(metrics, fn metric ->
      if metric.enabled do
        case Crontab.CronExpression.Parser.parse(metric.schedule) do
          {:ok, expr} ->
            if Crontab.DateChecker.matches_date?(expr, now) do
              enqueue_metric(metric, now)
            end

          {:error, reason} ->
            Logger.warning("Invalid metric cron: #{metric.schedule} (#{reason})")
        end
      end
    end)

    :ok
  end

  defp enqueue_metric(metric, now) do
    # Compute from/to based on granularity
    {from_ts, to_ts} =
      case metric.granularity do
        "minute" ->
          {DateTime.add(now, -60, :second) |> DateTime.truncate(:second), now}

        "hour" ->
          {DateTime.add(now, -3600, :second) |> DateTime.truncate(:second), now}

        "day" ->
          {DateTime.add(now, -86_400, :second) |> DateTime.truncate(:second), now}

        "week" ->
          {DateTime.add(now, -604_800, :second) |> DateTime.truncate(:second), now}

        "month" ->
          prev_month = Date.add(Date.new!(now.year, now.month, 1), -1)
          start_prev_month = DateTime.new!(prev_month, ~T[00:00:00], now.time_zone)
          {start_prev_month, now}

        _ ->
          {DateTime.add(now, -86_400, :second) |> DateTime.truncate(:second), now}
      end

    args = %{
      "metric_id" => metric.id,
      "from" => DateTime.to_iso8601(from_ts),
      "to" => DateTime.to_iso8601(to_ts)
    }

    QueryCanary.Jobs.MetricRunner.new(args)
    |> Oban.insert()
  end
end
