defmodule QueryCanary.ReportsTest do
  use QueryCanary.DataCase

  alias QueryCanary.Reports

  import QueryCanary.AccountsFixtures
  import QueryCanary.MetricsFixtures

  describe "reports" do
    test "create_report/2 stores personal ownership" do
      scope = user_scope_fixture()
      report_params = %{name: "Daily Overview", timezone: "Etc/UTC", default_range: "7d"}

      assert {:ok, report} = Reports.create_report(scope, report_params)
      assert report.user_id == scope.user.id
      assert report.team_id == nil
      assert report.settings["timeline_bucket"] == "day"
    end

    test "create_report/2 stores team ownership" do
      scope = user_scope_fixture()
      team = team_fixture(scope)

      params = %{
        name: "Team Dashboard",
        timezone: "America/New_York",
        default_range: "30d",
        team_id: team.id
      }

      assert {:ok, report} = Reports.create_report(scope, params)
      assert report.team_id == team.id
      assert report.user_id == nil
    end

    test "create_report/2 stores the report timeline bucket in settings" do
      scope = user_scope_fixture()

      params = %{
        name: "Weekly Team Dashboard",
        timezone: "America/New_York",
        default_range: "30d",
        settings: %{"timeline_bucket" => "week"}
      }

      assert {:ok, report} = Reports.create_report(scope, params)
      assert report.settings["timeline_bucket"] == "week"
    end

    test "create_report/2 accepts year-to-date as a default range" do
      scope = user_scope_fixture()

      params = %{
        name: "YTD Dashboard",
        timezone: "America/New_York",
        default_range: "ytd"
      }

      assert {:ok, report} = Reports.create_report(scope, params)
      assert report.default_range == "ytd"
    end

    test "list_reports/1 only returns accessible reports" do
      owner = user_scope_fixture()
      other = user_scope_fixture()

      {:ok, report} =
        Reports.create_report(owner, %{
          name: "Owner Report",
          timezone: "Etc/UTC",
          default_range: "today"
        })

      Reports.create_report(other, %{
        name: "Other Report",
        timezone: "Etc/UTC",
        default_range: "today"
      })

      reports = Reports.list_reports(owner)
      assert Enum.any?(reports, &(&1.id == report.id))
      refute Enum.any?(reports, &(&1.user_id == other.user.id))
    end
  end

  describe "report groups and metrics" do
    setup do
      scope = user_scope_fixture()
      metric = metric_fixture(scope)

      {:ok, report} =
        Reports.create_report(scope, %{
          name: "Operations",
          timezone: "Etc/UTC",
          default_range: "7d"
        })

      {:ok, group} = Reports.create_group(scope, report, %{name: "Key Metrics"})

      %{scope: scope, report: Reports.get_report!(scope, report.id), group: group, metric: metric}
    end

    test "create_group/3 appends with position", %{scope: scope, report: report} do
      {:ok, _} = Reports.create_group(scope, report, %{name: "Second"})

      refreshed = Reports.get_report!(scope, report.id)
      positions = Enum.map(refreshed.groups, & &1.position)
      assert positions == Enum.sort(positions)
    end

    test "add_metric_to_group/4 links metric to group", %{
      scope: scope,
      group: group,
      metric: metric
    } do
      assert {:ok, gm} = Reports.add_metric_to_group(scope, group, metric)
      assert gm.report_group_id == group.id
      assert gm.metric_id == metric.id
    end

    test "update_group_metric/3 stores display name", %{
      scope: scope,
      group: group,
      metric: metric
    } do
      {:ok, gm} = Reports.add_metric_to_group(scope, group, metric)

      assert {:ok, updated} =
               Reports.update_group_metric(scope, gm, %{settings: %{"display_name" => "Signups"}})

      assert updated.settings["display_name"] == "Signups"
    end

    test "remove_metric_from_group/2 deletes join record", %{
      scope: scope,
      group: group,
      metric: metric
    } do
      {:ok, gm} = Reports.add_metric_to_group(scope, group, metric)
      assert {:ok, _} = Reports.remove_metric_from_group(scope, gm)
      refreshed = Reports.get_report!(scope, group.report_id)
      assert Enum.empty?(hd(refreshed.groups).group_metrics)
    end

    test "move_metric_to_group/3 reassigns a metric to another group", %{
      scope: scope,
      report: report,
      group: group,
      metric: metric
    } do
      {:ok, gm} = Reports.add_metric_to_group(scope, group, metric)
      {:ok, target_group} = Reports.create_group(scope, report, %{name: "Secondary"})

      assert {:ok, moved} = Reports.move_metric_to_group(scope, gm, target_group)
      assert moved.report_group_id == target_group.id
    end

    test "move_metric_to_group/4 reorders metrics within the same group", %{
      scope: scope,
      report: report,
      group: group,
      metric: metric
    } do
      metric_two = metric_fixture(scope, %{name: "Second Metric"})
      metric_three = metric_fixture(scope, %{name: "Third Metric"})

      {:ok, gm_one} = Reports.add_metric_to_group(scope, group, metric)
      {:ok, gm_two} = Reports.add_metric_to_group(scope, group, metric_two)
      {:ok, gm_three} = Reports.add_metric_to_group(scope, group, metric_three)

      assert {:ok, _moved} =
               Reports.move_metric_to_group(
                 scope,
                 gm_three,
                 group,
                 before_group_metric_id: gm_one.id
               )

      refreshed = Reports.get_report!(scope, report.id)
      [refreshed_group | _] = refreshed.groups

      assert Enum.map(refreshed_group.group_metrics, & &1.id) == [
               gm_three.id,
               gm_one.id,
               gm_two.id
             ]

      assert Enum.map(refreshed_group.group_metrics, & &1.position) == [0, 1, 2]
    end
  end
end
