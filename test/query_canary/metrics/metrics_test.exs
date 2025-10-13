defmodule QueryCanary.MetricsTest do
  use QueryCanary.DataCase, async: false

  alias QueryCanary.Metrics

  import QueryCanary.AccountsFixtures

  @tag :database_adapters
  test "create and run metric stores result once" do
    scope = user_scope_fixture()

    {:ok, server} =
      QueryCanary.Servers.create_server(scope, %{
        name: "Test PG",
        db_engine: "postgresql",
        db_hostname: System.get_env("PG_HOST", "127.0.0.1"),
        db_port: String.to_integer(System.get_env("PG_PORT", "55432")),
        db_name: System.get_env("PG_DATABASE", "postgres"),
        db_username: System.get_env("PG_USER", "postgres"),
        db_password_input: System.get_env("PG_PASSWORD", "postgres"),
        db_ssl_mode: System.get_env("PG_SSL_MODE", "disable")
      })

    {:ok, metric} =
      Metrics.create_metric(%{
        name: "Count",
        sql: "select 1",
        schedule: "* * * * *",
        granularity: "day",
        server_id: server.id
      })

    from_ts = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
    to_ts = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _} = Metrics.run_metric_range(metric, from_ts, to_ts)
    assert {:ok, _} = Metrics.run_metric_range(metric, from_ts, to_ts)

    count =
      QueryCanary.Repo.aggregate(
        from(r in QueryCanary.Metrics.MetricResult, where: r.metric_id == ^metric.id),
        :count
      )

    assert count == 1
  end

  test "window range" do
    {:ok, from, 0} = DateTime.from_iso8601("2025-03-01T00:00:00Z")
    {:ok, to, 0} = DateTime.from_iso8601("2025-03-03T00:00:00Z")

    windows =
      Metrics.windows_for_range(
        "day",
        from,
        to,
        "Etc/UTC"
      )

    assert [
             {~U[2025-03-01 00:00:00Z], ~U[2025-03-02 00:00:00Z]},
             {~U[2025-03-02 00:00:00Z], ~U[2025-03-03 00:00:00Z]}
           ] = windows
  end
end
