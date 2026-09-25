defmodule QueryCanaryWeb.NotificationSettingsTest do
  use QueryCanaryWeb.ConnCase
  import Phoenix.LiveViewTest
  import QueryCanary.AccountsFixtures
  import QueryCanary.ServersFixtures
  import QueryCanary.ChecksFixtures
  import QueryCanary.NotificationsFixtures
  alias QueryCanary.{Accounts, Checks, Notifications}
  alias QueryCanary.Notifications.Slack

  setup :register_and_log_in_user

  setup %{scope: scope} do
    team = team_fixture(scope)
    integration_fixture(scope, team)
    server = server_fixture(scope, %{team_id: team.id})
    check = check_fixture(scope, %{server_id: server.id})

    Req.Test.stub(
      Slack,
      &Req.Test.json(&1, %{
        ok: true,
        channels: [
          %{id: "C12345678", name: "ops", is_member: true},
          %{id: "G87654321", name: "private-alerts", is_member: true}
        ]
      })
    )

    %{team: team, server: server, check: check}
  end

  test "check settings save, display, and disable a channel", ctx do
    {:ok, view, html} = live(ctx.conn, ~p"/checks/#{ctx.check}/edit")
    assert html =~ "#ops"
    assert html =~ "#private-alerts"

    view
    |> form("#check-form", check: %{notification_channels: %{slack: "G87654321"}})
    |> render_submit()

    assert Notifications.channels_for_check(ctx.check) == %{"slack" => "G87654321"}

    {:ok, view, _} = live(ctx.conn, ~p"/checks/#{ctx.check}/edit")
    assert has_element?(view, "#check-slack-channel option[selected][value='G87654321']")
    view |> form("#check-form", check: %{notification_channels: %{slack: ""}}) |> render_submit()
    assert Notifications.channels_for_check(ctx.check) == %{}
  end

  test "the result-history canvas uses the same data as notification snapshots", ctx do
    alert_result_fixture(ctx.check, %{result: [%{"count" => 100}], is_alert: false})

    latest =
      alert_result_fixture(ctx.check, %{
        result: [%{"count" => 200}],
        alert_type: :anomaly,
        analysis_details: %{
          "mean" => 100,
          "std_dev" => 5,
          "current_value" => 200,
          "z_score" => 20
        }
      })

    {:ok, _view, html} = live(ctx.conn, ~p"/checks/#{ctx.check}")

    [data] =
      html
      |> Floki.parse_document!()
      |> Floki.find("#results-chart")
      |> Floki.attribute("data-chart")

    expected =
      latest
      |> Checks.get_results_through()
      |> Checks.ChartData.from_results()
      |> Jason.encode!()
      |> Jason.decode!()

    assert Jason.decode!(data) == expected
  end

  test "quickstart offers the team's channels when creating a check", ctx do
    {:ok, view, html} = live(ctx.conn, ~p"/quickstart/check?server_id=#{ctx.server.id}")
    assert html =~ "#ops"
    assert has_element?(view, "#check-email-notifications[checked]")
    assert has_element?(view, "#check-slack-notifications[checked]")

    refute view
           |> form("#check-form",
             check: %{
               name: "New check",
               notification_channels: %{slack: "C12345678"}
             }
           )
           |> render_change() =~ "select a valid"

    view
    |> form("#check-form", check: %{notification_preferences: %{email: false, slack: false}})
    |> render_change()

    refute has_element?(view, "#check-email-notifications[checked]")
    refute has_element?(view, "#check-slack-notifications[checked]")
  end

  test "toggles persist independently and keep the saved Slack channel", ctx do
    {:ok, check} =
      Checks.update_check(ctx.scope, ctx.check, %{
        notification_channels: %{"slack" => "C12345678"}
      })

    {:ok, view, _} = live(ctx.conn, ~p"/checks/#{check}/edit")

    view
    |> form("#check-form", check: %{notification_preferences: %{email: false, slack: false}})
    |> render_submit()

    {:ok, view, _} = live(ctx.conn, ~p"/checks/#{check}/edit")
    refute has_element?(view, "#check-email-notifications[checked]")
    refute has_element?(view, "#check-slack-notifications[checked]")
    assert has_element?(view, "#check-slack-channel option[selected][value='C12345678']")
    assert Notifications.channels_for_check(check) == %{"slack" => "C12345678"}

    view
    |> form("#check-form", check: %{notification_preferences: %{slack: true}})
    |> render_submit()

    saved = Checks.get_check!(ctx.scope, check.id)
    refute Notifications.enabled?(saved, "email")
    assert Notifications.enabled?(saved, "slack")
    assert saved.enabled == check.enabled
  end

  test "an API failure preserves saved channels through an unrelated edit", ctx do
    {:ok, check} =
      Checks.update_check(ctx.scope, ctx.check, %{
        notification_channels: %{"slack" => "C12345678"}
      })

    Req.Test.stub(Slack, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    {:ok, view, html} = live(ctx.conn, ~p"/checks/#{check}/edit")
    assert html =~ "Channels could not be loaded"
    assert has_element?(view, "#check-slack-channel option[selected][value='C12345678']")
    view |> form("#check-form", check: %{name: "Renamed"}) |> render_submit()
    assert Notifications.channels_for_check(check) == %{"slack" => "C12345678"}
  end

  test "admin can disconnect from team settings without displaying credentials", ctx do
    {:ok, view, html} = live(ctx.conn, ~p"/teams/#{ctx.team}")
    assert html =~ "Canary workspace"
    refute html =~ "xoxb-test-secret"
    view |> element("button", "Disconnect Slack") |> render_click()
    assert Notifications.list_integrations(ctx.scope, ctx.team.id) == []
    refute has_element?(view, "#slack-connection")
  end

  test "a member may choose channels but cannot disconnect with a forged event", ctx do
    member = user_scope_fixture()
    {:ok, _} = Accounts.invite_user_to_team(ctx.scope, ctx.team, member.user.email)
    {:ok, _} = Accounts.accept_team_invite(member, ctx.team)
    conn = build_conn() |> log_in_user(member.user)
    {:ok, view, _} = live(conn, ~p"/teams/#{ctx.team}")
    refute has_element?(view, "button", "Disconnect Slack")
    assert render_click(view, "disconnect_slack") =~ "Only team admins"
    assert [_] = Notifications.list_integrations(ctx.scope, ctx.team.id)

    {:ok, view, _} = live(conn, ~p"/checks/#{ctx.check}/edit")

    view
    |> form("#check-form", check: %{notification_channels: %{slack: "C12345678"}})
    |> render_submit()

    assert Notifications.channels_for_check(ctx.check) == %{"slack" => "C12345678"}
  end

  test "personal checks explain team ownership", ctx do
    check = check_fixture(ctx.scope)
    {:ok, view, html} = live(ctx.conn, ~p"/checks/#{check}/edit")
    assert html =~ "team-owned servers"
    refute has_element?(view, "#check-slack-channel")
    assert has_element?(view, "#check-email-notifications[checked]")

    view
    |> form("#check-form", check: %{notification_preferences: %{email: false}})
    |> render_submit()

    refute Notifications.enabled?(Checks.get_check!(ctx.scope, check.id), "email")
  end
end
