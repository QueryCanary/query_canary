defmodule QueryCanary.Jobs.MetricRunner do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias QueryCanary.Metrics

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"metric_id" => metric_id, "from" => from, "to" => to}}) do
    metric = Metrics.get_metric!(metric_id)
    {:ok, from_ts, 0} = DateTime.from_iso8601(from)
    {:ok, to_ts, 0} = DateTime.from_iso8601(to)

    case Metrics.run_metric_range(metric, from_ts, to_ts) do
      {:ok, _res} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
