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
  end
end
