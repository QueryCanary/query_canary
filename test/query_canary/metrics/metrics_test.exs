defmodule QueryCanary.MetricsTest do
  use QueryCanary.DataCase, async: false

  alias QueryCanary.Metrics
  alias QueryCanary.Metrics.MetricResult
  alias QueryCanary.Jobs.MetricBackfillEnqueuer

  import QueryCanary.AccountsFixtures
  import QueryCanary.MetricsFixtures

  test "backfill enqueuer deletes older metric values before queuing fresh runs" do
    scope = user_scope_fixture()

    metric =
      metric_fixture(scope, %{
        name: "Daily Signups",
        sql: "select 1 as value",
        granularity: "day",
        timezone: "Etc/UTC"
      })

    from_dt = ~U[2025-03-01 00:00:00Z]
    mid_dt = ~U[2025-03-02 00:00:00Z]
    to_dt = ~U[2025-03-03 00:00:00Z]
    outside_to_dt = ~U[2025-03-04 00:00:00Z]

    Repo.insert!(%MetricResult{
      metric_id: metric.id,
      from_ts: from_dt,
      to_ts: mid_dt,
      value: Decimal.new(10),
      payload: %{}
    })

    Repo.insert!(%MetricResult{
      metric_id: metric.id,
      from_ts: mid_dt,
      to_ts: to_dt,
      value: Decimal.new(12),
      payload: %{}
    })

    Repo.insert!(%MetricResult{
      metric_id: metric.id,
      from_ts: to_dt,
      to_ts: outside_to_dt,
      value: Decimal.new(15),
      payload: %{}
    })

    assert :ok =
             MetricBackfillEnqueuer.perform(%Oban.Job{
               args: %{
                 "metric_id" => metric.id,
                 "from" => DateTime.to_iso8601(from_dt),
                 "to" => DateTime.to_iso8601(to_dt)
               }
             })

    remaining_results =
      Repo.all(
        from r in MetricResult,
          where: r.metric_id == ^metric.id,
          order_by: [asc: r.from_ts]
      )

    assert Enum.map(remaining_results, &{&1.from_ts, &1.to_ts}) == [{to_dt, outside_to_dt}]

    queued_jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.worker == "QueryCanary.Jobs.MetricRunner",
          order_by: [asc: j.id]
      )

    assert Enum.map(queued_jobs, & &1.queue) == ["metric_backfill", "metric_backfill"]
    assert Enum.map(queued_jobs, &{&1.args["from"], &1.args["to"]}) == [
             {DateTime.to_iso8601(from_dt), DateTime.to_iso8601(mid_dt)},
             {DateTime.to_iso8601(mid_dt), DateTime.to_iso8601(to_dt)}
           ]

    [first_job, second_job] = queued_jobs
    assert DateTime.compare(second_job.scheduled_at, first_job.scheduled_at) == :gt
  end

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
        granularity: "day",
        server_id: server.id
      })

    assert metric.schedule == "0 8 * * *"

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
