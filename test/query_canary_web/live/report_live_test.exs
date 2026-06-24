defmodule QueryCanaryWeb.ReportLiveTest do
  use QueryCanaryWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import QueryCanary.MetricsFixtures

  alias Decimal
  alias QueryCanary.Metrics
  alias QueryCanary.Metrics.MetricResult
  alias QueryCanary.Repo
  alias QueryCanary.Reports

  setup :register_and_log_in_user

  describe "Show" do
    setup [:create_report_with_metric]

    test "opens a metric details modal with previous values", %{
      conn: conn,
      report: report,
      metric: metric,
      group_metric: group_metric
    } do
      {:ok, show_live, html} = live(conn, ~p"/reports/#{report.id}")

      assert html =~ "Daily Signups"
      refute has_element?(show_live, "#metric-details-modal")

      show_live
      |> element("#metric-title-#{group_metric.id}")
      |> render_click()

      assert has_element?(show_live, "#metric-details-modal")

      modal_html = render(show_live)
      assert modal_html =~ "Metric Details"
      assert modal_html =~ metric.sql
      assert modal_html =~ "No description provided."
      assert modal_html =~ "Previous values"
      assert modal_html =~ "120"
      assert modal_html =~ "115"

      show_live
      |> element("#close-metric-details")
      |> render_click()

      refute has_element?(show_live, "#metric-details-modal")
    end

    test "edits metric details inside the modal", %{
      conn: conn,
      report: report,
      metric: metric,
      group_metric: group_metric
    } do
      {:ok, show_live, _html} = live(conn, ~p"/reports/#{report.id}")

      show_live
      |> element("#metric-title-#{group_metric.id}")
      |> render_click()

      show_live
      |> element("#edit-metric-details")
      |> render_click()

      assert has_element?(show_live, "#selected-metric-form")

      show_live
      |> form("#selected-metric-form",
        metric: %{
          name: "Updated Signup Count",
          description: "",
          sql: metric.sql,
          granularity: "hour",
          timezone: "Etc/UTC",
          enabled: "true",
          server_id: Integer.to_string(metric.server_id)
        }
      )
      |> render_submit()

      updated_metric = Metrics.get_metric!(metric.id)
      assert updated_metric.name == "Updated Signup Count"
      assert updated_metric.sql == metric.sql
      assert updated_metric.schedule == "0 8 * * *"
      assert updated_metric.granularity == "hour"

      html = render(show_live)
      refute html =~ "id=\"selected-metric-form\""
      assert html =~ "Updated Signup Count"
      assert html =~ metric.sql
    end

    test "auto backfills from the modal without leaving the page", %{
      conn: conn,
      report: report,
      group_metric: group_metric
    } do
      {:ok, show_live, _html} = live(conn, ~p"/reports/#{report.id}")

      show_live
      |> element("#metric-title-#{group_metric.id}")
      |> render_click()

      assert has_element?(show_live, "#metric-details-modal")

      show_live
      |> element("#metric-auto-backfill")
      |> render_click()

      assert has_element?(show_live, "#metric-details-modal")
      assert render(show_live) =~ "Backfill enqueued"

      job =
        Repo.one!(
          from j in Oban.Job,
            where: j.worker == "QueryCanary.Jobs.MetricBackfillEnqueuer",
            order_by: [desc: j.id],
            limit: 1
        )

      assert job.worker == "QueryCanary.Jobs.MetricBackfillEnqueuer"

      {:ok, from_dt, 0} = DateTime.from_iso8601(job.args["from"])
      {:ok, to_dt, 0} = DateTime.from_iso8601(job.args["to"])
      assert Date.diff(DateTime.to_date(to_dt), DateTime.to_date(from_dt)) == 30
    end

    test "creates a new metric directly from the report group", %{
      conn: conn,
      report: report,
      group: group,
      metric: metric,
      scope: scope
    } do
      {:ok, show_live, _html} = live(conn, ~p"/reports/#{report.id}")

      show_live
      |> element("button[phx-click='start_create_metric'][phx-value-id='#{group.id}']")
      |> render_click()

      assert has_element?(show_live, "#new-metric-modal")
      assert has_element?(show_live, "#new-metric-form-#{group.id}")

      show_live
      |> form("#new-metric-form-#{group.id}",
        group_id: Integer.to_string(group.id),
        metric: %{
          name: "Revenue",
          description: "",
          sql: "select 42 as value",
          granularity: "day",
          timezone: "Etc/UTC",
          enabled: "true",
          server_id: Integer.to_string(metric.server_id)
        }
      )
      |> render_submit()

      assert Enum.any?(Metrics.list_metrics_for_scope(scope), &(&1.name == "Revenue"))
      assert render(show_live) =~ "Revenue"
    end

    test "refreshes when metric results are updated", %{
      conn: conn,
      report: report,
      metric: metric,
      group_metric: group_metric
    } do
      {:ok, show_live, _html} = live(conn, ~p"/reports/#{report.id}")

      show_live
      |> element("#metric-title-#{group_metric.id}")
      |> render_click()

      refute has_element?(show_live, "[title*=': 88']")

      insert_metric_result(metric.id, 3, 88)
      send(show_live.pid, {:metric_result_updated, metric.id})

      assert has_element?(show_live, "[title*=': 88']")
    end

    test "rolls daily metric values into weekly report buckets", %{conn: conn, scope: scope} do
      metric =
        metric_fixture(scope, %{
          name: "New Users",
          sql: "select count(*) as value from users",
          granularity: "day",
          timezone: "Etc/UTC"
        })

      {:ok, report} =
        Reports.create_report(scope, %{
          name: "Weekly Growth",
          timezone: "Etc/UTC",
          default_range: "30d",
          settings: %{"timeline_bucket" => "week"}
        })

      {:ok, group} = Reports.create_group(scope, report, %{name: "Growth"})
      {:ok, group_metric} = Reports.add_metric_to_group(scope, group, metric)

      today = Date.utc_today()
      current_week_start = Date.add(today, 1 - Date.day_of_week(today))
      previous_week_start = Date.add(current_week_start, -7)
      two_weeks_ago_start = Date.add(current_week_start, -14)

      insert_metric_result_on(metric.id, two_weeks_ago_start, 8)
      insert_metric_result_on(metric.id, Date.add(two_weeks_ago_start, 2), 9)
      insert_metric_result_on(metric.id, previous_week_start, 10)
      insert_metric_result_on(metric.id, Date.add(previous_week_start, 1), 11)
      insert_metric_result_on(metric.id, Date.add(previous_week_start, 2), 28)

      {:ok, show_live, html} = live(conn, ~p"/reports/#{report.id}")

      assert html =~ "Timeline: weekly"
      assert has_element?(show_live, "#metric-title-#{group_metric.id}")
      assert has_element?(show_live, "[title*='Week of'][title*='17']")
      assert has_element?(show_live, "[title*='Week of'][title*='49']")
    end
  end

  defp create_report_with_metric(%{scope: scope}) do
    metric =
      metric_fixture(scope, %{
        name: "Signup Count",
        sql: "select count(*) as value from signups",
        granularity: "day",
        timezone: "Etc/UTC"
      })

    {:ok, report} =
      Reports.create_report(scope, %{
        name: "Executive Overview",
        timezone: "Etc/UTC",
        default_range: "7d"
      })

    {:ok, group} = Reports.create_group(scope, report, %{name: "Growth"})

    {:ok, group_metric} =
      Reports.add_metric_to_group(scope, group, metric, %{
        settings: %{"display_name" => "Daily Signups"}
      })

    insert_metric_result(metric.id, 0, 120)
    insert_metric_result(metric.id, 1, 115)
    insert_metric_result(metric.id, 2, 98)

    %{
      report: Reports.get_report!(scope, report.id),
      group: group,
      metric: metric,
      group_metric: group_metric
    }
  end

  defp insert_metric_result(metric_id, days_ago, value) do
    from_date = Date.add(Date.utc_today(), -days_ago)
    insert_metric_result_on(metric_id, from_date, value)
  end

  defp insert_metric_result_on(metric_id, from_date, value) do
    to_date = Date.add(from_date, 1)

    Repo.insert!(%MetricResult{
      metric_id: metric_id,
      from_ts: DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC"),
      to_ts: DateTime.new!(to_date, ~T[00:00:00], "Etc/UTC"),
      value: Decimal.new(value),
      payload: %{}
    })
  end
end
