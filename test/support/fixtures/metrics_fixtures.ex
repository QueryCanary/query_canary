defmodule QueryCanary.MetricsFixtures do
  @moduledoc false

  import QueryCanary.ServersFixtures

  alias QueryCanary.Metrics

  def metric_fixture(scope, attrs \\ %{}) do
    server = Map.get(attrs, :server) || Map.get(attrs, "server") || server_fixture(scope)

    attrs =
      attrs
      |> Map.drop([:server])
      |> Map.merge(%{
        name: Map.get(attrs, :name, "Metric #{System.unique_integer()}"),
        sql: Map.get(attrs, :sql, "select 1 as value"),
        schedule: Map.get(attrs, :schedule, "* * * * *"),
        granularity: Map.get(attrs, :granularity, "day"),
        timezone: Map.get(attrs, :timezone, "Etc/UTC"),
        enabled: Map.get(attrs, :enabled, true),
        server_id: Map.get(attrs, :server_id, server.id),
        user_id: Map.get(attrs, :user_id, scope.user.id)
      })

    {:ok, metric} = Metrics.create_metric(attrs)
    %{metric | server: server}
  end
end
