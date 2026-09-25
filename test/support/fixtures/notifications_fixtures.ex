defmodule QueryCanary.NotificationsFixtures do
  def installation(attrs \\ %{}) do
    Map.merge(
      %{external_id: "T12345678", name: "Canary workspace", token: "xoxb-test-secret"},
      attrs
    )
  end

  def integration_fixture(scope, team, attrs \\ %{}) do
    {:ok, integration} =
      QueryCanary.Notifications.connect_slack(scope, team.id, installation(attrs))

    integration
  end

  def alert_result_fixture(check, attrs \\ %{}) do
    {:ok, result} =
      QueryCanary.Checks.create_check_result(
        Map.merge(
          %{
            check_id: check.id,
            result: [],
            success: true,
            time_taken: 1,
            is_alert: true,
            alert_type: :diff,
            analysis_summary: "Row count changed"
          },
          attrs
        )
      )

    result
  end
end
