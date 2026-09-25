defmodule QueryCanary.NotificationsTest do
  use QueryCanary.DataCase, async: true
  use Oban.Testing, repo: QueryCanary.Repo
  import QueryCanary.AccountsFixtures
  import QueryCanary.ServersFixtures
  import QueryCanary.ChecksFixtures
  import QueryCanary.NotificationsFixtures
  alias QueryCanary.{Accounts, Checks, Notifications}
  alias QueryCanary.Notifications.{Integration, Destination, Slack}
  alias QueryCanary.Jobs.DeliverNotification

  setup do
    scope = user_scope_fixture()
    team = team_fixture(scope)
    integration = integration_fixture(scope, team)
    server = server_fixture(scope, %{team_id: team.id})

    check =
      check_fixture(scope, %{
        server_id: server.id,
        notification_channels: %{"slack" => "C12345678"}
      })

    %{scope: scope, team: team, integration: integration, server: server, check: check}
  end

  test "one encrypted connection per team; reinstall refreshes credentials and preserves routes",
       ctx do
    updated = integration_fixture(ctx.scope, ctx.team, %{token: "xoxb-new-secret"})
    assert updated.id == ctx.integration.id
    assert Repo.aggregate(Integration, :count) == 1
    assert {:ok, "xoxb-new-secret"} = Integration.token(Repo.get!(Integration, updated.id))
    refute updated.encrypted_token =~ "xoxb-new-secret"
    refute inspect(updated) =~ updated.encrypted_token
    assert Notifications.channels_for_check(ctx.check) == %{"slack" => "C12345678"}
    [metadata] = Notifications.list_integrations(ctx.scope, ctx.team.id)
    refute Map.has_key?(metadata, :encrypted_token)
  end

  test "only admins manage connections and only accepted members see them", ctx do
    member = user_scope_fixture()
    {:ok, _} = Accounts.invite_user_to_team(ctx.scope, ctx.team, member.user.email)
    assert Notifications.list_integrations(member, ctx.team.id) == []
    assert {:error, :not_connected} = Notifications.list_channels(member, ctx.team.id, "slack")
    assert {:error, :forbidden} = Notifications.connect_slack(member, ctx.team.id, installation())

    for channel <- ["C12345678", ""] do
      assert {:error, changeset} =
               Checks.update_check(member, ctx.check, %{
                 notification_channels: %{"slack" => channel}
               })

      assert "only active members can configure team alerts" in errors_on(changeset).notification_channels
    end

    {:ok, _} = Accounts.accept_team_invite(member, ctx.team)
    assert [_] = Notifications.list_integrations(member, ctx.team.id)
    assert {:error, :forbidden} = Notifications.disconnect(member, ctx.team.id, "slack")
    assert {:error, :forbidden} = Notifications.connect_slack(member, ctx.team.id, installation())
    assert Notifications.list_integrations(user_scope_fixture(), ctx.team.id) == []
    assert {:error, :forbidden} = Notifications.connect_slack(ctx.scope, nil, installation())
  end

  test "each check selects a channel on its team's connection", ctx do
    other =
      check_fixture(ctx.scope, %{
        server_id: ctx.server.id,
        notification_channels: %{"slack" => "G87654321"}
      })

    assert Notifications.channels_for_check(ctx.check) == %{"slack" => "C12345678"}
    assert Notifications.channels_for_check(other) == %{"slack" => "G87654321"}

    assert Repo.all(from d in Destination, select: d.integration_id) == [
             ctx.integration.id,
             ctx.integration.id
           ]
  end

  test "personal checks and other teams cannot use this connection", ctx do
    personal = check_fixture(ctx.scope)
    other_team = team_fixture(ctx.scope)
    other_server = server_fixture(ctx.scope, %{team_id: other_team.id})
    other = check_fixture(ctx.scope, %{server_id: other_server.id})

    for check <- [personal, other] do
      assert {:error, changeset} =
               Checks.update_check(ctx.scope, check, %{
                 notification_channels: %{"slack" => "C12345678"}
               })

      assert errors_on(changeset).notification_channels != []
    end
  end

  test "invalid destination changes roll back the check edit", ctx do
    for channels <- [%{"slack" => "#channel"}, %{"slack" => %{}}, %{"discord" => "123"}] do
      assert {:error, changeset} =
               Checks.update_check(ctx.scope, ctx.check, %{
                 name: "Should not save",
                 notification_channels: channels
               })

      assert errors_on(changeset).notification_channels != []
    end

    assert Repo.get!(Checks.Check, ctx.check.id).name == ctx.check.name
  end

  test "unrelated edits preserve channels and blank explicitly disables chat", ctx do
    assert {:ok, check} = Checks.update_check(ctx.scope, ctx.check, %{name: "Renamed"})
    assert Notifications.channels_for_check(check) == %{"slack" => "C12345678"}

    assert {:ok, check} =
             Checks.update_check(ctx.scope, check, %{notification_channels: %{"slack" => ""}})

    assert Notifications.channels_for_check(check) == %{}
  end

  test "email fanout adds exactly one chat job and repeated enqueues are deduplicated", ctx do
    member = user_scope_fixture()
    {:ok, _} = Accounts.invite_user_to_team(ctx.scope, ctx.team, member.user.email)
    {:ok, _} = Accounts.accept_team_invite(member, ctx.team)

    result =
      alert_result_fixture(ctx.check, %{
        analysis_details: %{
          "previous_value" => 100,
          "current_value" => 150,
          "percent_change" => 0.5
        }
      })
      |> Repo.reload!()

    assert {:ok, :notification_sent} = Checks.maybe_send_check_notification(ctx.check, result)

    subject = "⚠️ Alert: Test Check - Significant Change Detected"
    owner_email = ctx.scope.user.email
    member_email = member.user.email
    assert_received {:email, %{subject: ^subject, to: [{_, ^owner_email}]} = email}
    assert email.text_body =~ "Current value: 150"
    assert email.text_body =~ "Change: 50.0%"
    assert [chart] = email.attachments
    assert chart.filename == "querycanary-#{ctx.check.id}-#{result.id}.png"
    assert chart.content_type == "image/png"
    assert chart.type == :inline
    assert chart.cid == chart.filename
    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = chart.data
    assert email.html_body =~ ~s(src="cid:#{chart.cid}")
    assert email.html_body =~ "Result History"

    assert_received {:email, %{subject: ^subject, to: [{_, ^member_email}]} = member_alert}
    assert [member_chart] = member_alert.attachments
    assert member_chart.data == chart.data

    Notifications.enqueue_alert(ctx.check, result)
    assert [%{args: %{"check_result_id" => id}}] = all_enqueued(worker: DeliverNotification)
    assert id == result.id
  end

  test "non-alerts never queue chat", ctx do
    result = alert_result_fixture(ctx.check, %{is_alert: false})
    assert {:ok, :no_alert} = Checks.maybe_send_check_notification(ctx.check, result)
    refute_enqueued(worker: DeliverNotification)
  end

  test "notification types default to enabled and partial updates preserve other toggles", ctx do
    assert Notifications.enabled?(ctx.check, "email")
    assert Notifications.enabled?(ctx.check, "slack")

    assert {:ok, check} =
             Checks.update_check(ctx.scope, ctx.check, %{
               notification_preferences: %{"email" => "false", "slack" => "false"}
             })

    assert check.notification_preferences == %{"email" => false, "slack" => false}

    assert {:ok, check} =
             Checks.update_check(ctx.scope, check, %{
               notification_preferences: %{"email" => "true"}
             })

    assert Repo.get!(Checks.Check, check.id).notification_preferences == %{
             "email" => true,
             "slack" => false
           }

    assert {:ok, check} = Checks.update_check(ctx.scope, check, %{name: "Renamed"})
    refute Notifications.enabled?(check, "slack")
    assert check.enabled
    assert Notifications.channels_for_check(check) == %{"slack" => "C12345678"}
  end

  test "email and Slack toggles independently control delivery using current settings", ctx do
    for email_enabled <- [true, false], slack_enabled <- [true, false] do
      check =
        check_fixture(ctx.scope, %{
          name: "Email #{email_enabled} Slack #{slack_enabled}",
          server_id: ctx.server.id,
          notification_channels: %{"slack" => "C12345678"}
        })

      result = alert_result_fixture(check)

      {:ok, _} =
        Checks.update_check(ctx.scope, check, %{
          notification_preferences: %{"email" => email_enabled, "slack" => slack_enabled}
        })

      # Pass the original struct to simulate toggling notifications during a running query.
      expected =
        if email_enabled or slack_enabled, do: :notification_sent, else: :notifications_disabled

      assert {:ok, ^expected} = Checks.maybe_send_check_notification(check, result)
      subject = "⚠️ Alert: #{check.name} - Significant Change Detected"

      if email_enabled do
        assert_received {:email, %{subject: ^subject}}
      else
        refute_received {:email, %{subject: ^subject}}
      end

      jobs = all_enqueued(worker: DeliverNotification, args: %{check_result_id: result.id})
      assert length(jobs) == if(slack_enabled, do: 1, else: 0)
      assert Repo.get!(Checks.Check, check.id).enabled
    end

    assert Notifications.enabled?(Repo.get!(Checks.Check, ctx.check.id), "email")
    assert Notifications.enabled?(Repo.get!(Checks.Check, ctx.check.id), "slack")
  end

  test "personal check email notifications can be turned off", ctx do
    check = check_fixture(ctx.scope, %{notification_preferences: %{"email" => false}})
    result = alert_result_fixture(check)
    assert {:ok, :notifications_disabled} = Checks.maybe_send_check_notification(check, result)
    refute_received {:email, %{subject: "⚠️ Alert: Test Check - Significant Change Detected"}}
    refute_enqueued(worker: DeliverNotification)

    assert {:ok, :notifications_disabled} =
             Checks.CheckNotifier.deliver_check_alert_notification(
               ctx.scope.user,
               check,
               result,
               "https://querycanary.com/checks/#{check.id}"
             )
  end

  test "email alert still sends its details when the chart is unavailable", ctx do
    result = alert_result_fixture(ctx.check, %{analysis_details: %{"current_value" => 150}})
    url = "https://querycanary.com/checks/#{ctx.check.id}"

    assert {:ok, email} =
             Checks.CheckNotifier.deliver_check_alert_notification(
               ctx.scope.user,
               ctx.check,
               result,
               url,
               nil
             )

    assert email.attachments == []
    refute email.html_body =~ "cid:"
    assert email.html_body =~ "Current value"
    assert email.text_body =~ "Current value: 150"
    assert email.html_body =~ url
  end

  test "invalid preferences cannot erase or silently enable notification settings", ctx do
    for preferences <- [%{"email" => "invalid"}, %{"slack" => nil}, %{"discord" => false}, nil] do
      assert {:error, changeset} =
               Checks.update_check(ctx.scope, ctx.check, %{notification_preferences: preferences})

      assert errors_on(changeset).notification_preferences != []
    end
  end

  test "invited members cannot mute a team's notifications", ctx do
    invited = user_scope_fixture()
    {:ok, _} = Accounts.invite_user_to_team(ctx.scope, ctx.team, invited.user.email)

    assert {:error, changeset} =
             Checks.update_check(invited, ctx.check, %{
               notification_preferences: %{"email" => false, "slack" => false}
             })

    assert "only active members can configure team alerts" in errors_on(changeset).notification_preferences
  end

  test "muting Slack cancels pending deliveries and keeps the channel for future alerts", ctx do
    result = alert_result_fixture(ctx.check)
    args = job_args(ctx.check, result)
    {:ok, _} = Notifications.enqueue_alert(ctx.check, result)

    {:ok, check} =
      Checks.update_check(ctx.scope, ctx.check, %{notification_preferences: %{"slack" => false}})

    assert {:cancel, :notifications_disabled} = perform_job(DeliverNotification, args)
    assert Notifications.channels_for_check(check) == %{"slack" => "C12345678"}

    {:ok, check} =
      Checks.update_check(ctx.scope, check, %{notification_preferences: %{"slack" => true}})

    new_result = alert_result_fixture(check)
    {:ok, _} = Notifications.enqueue_alert(check, new_result)
    assert_enqueued(worker: DeliverNotification, args: %{check_result_id: new_result.id})

    expect_chart_upload()

    Req.Test.expect(Slack, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["channel"] == "C12345678"
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = perform_job(DeliverNotification, job_args(check, new_result))
  end

  test "worker posts the result's alert to the selected channel", ctx do
    alert_result_fixture(ctx.check, %{result: [%{"count" => 100}], is_alert: false})

    result =
      alert_result_fixture(ctx.check, %{
        result: [%{"count" => 150}],
        analysis_details: %{
          "previous_value" => 100,
          "current_value" => 150,
          "percent_change" => 0.5
        }
      })

    expect_chart_upload()

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/chat.postMessage"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer xoxb-test-secret"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["channel"] == "C12345678"
      assert payload["text"] =~ "Row count changed"
      assert payload["text"] =~ "/checks/#{ctx.check.id}"
      assert payload["unfurl_links"] == false
      assert payload["text"] =~ "Current value: 150"
      assert payload["text"] =~ "Change: 50.0%"
      assert Enum.any?(payload["blocks"], &(&1["slack_file"] == %{"id" => "F12345678"}))
      Req.Test.json(conn, %{ok: true})
    end)

    assert :ok = perform_job(DeliverNotification, job_args(ctx.check, result))
  end

  test "chart history is bounded, scoped to its check and ends at the triggering result", ctx do
    at = ~U[2026-09-25 12:00:00Z]

    for _ <- 1..50 do
      alert_result_fixture(ctx.check)
      |> Ecto.Changeset.change(inserted_at: DateTime.add(at, -60))
      |> Repo.update!()
    end

    result =
      alert_result_fixture(ctx.check) |> Ecto.Changeset.change(inserted_at: at) |> Repo.update!()

    # Same-second later runs must also be excluded.
    alert_result_fixture(ctx.check) |> Ecto.Changeset.change(inserted_at: at) |> Repo.update!()

    alert_result_fixture(ctx.check)
    |> Ecto.Changeset.change(inserted_at: DateTime.add(at, 60))
    |> Repo.update!()

    other = check_fixture(ctx.scope, %{server_id: ctx.server.id})

    alert_result_fixture(other)
    |> Ecto.Changeset.change(inserted_at: DateTime.add(at, -30))
    |> Repo.update!()

    history = Checks.get_results_through(result)
    assert length(history) == 48
    assert hd(history).id == result.id
    assert Enum.all?(history, &(&1.check_id == ctx.check.id and &1.id <= result.id))
  end

  test "rate limits snooze, temporary failures retry, revoked tokens cancel", ctx do
    result = alert_result_fixture(ctx.check)
    args = job_args(ctx.check, result)

    Req.Test.stub(Slack, fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "17") |> Plug.Conn.send_resp(429, "")
    end)

    assert {:snooze, 17} = perform_job(DeliverNotification, args)
    Req.Test.stub(Slack, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    assert {:error, {:http, 503}} = perform_job(DeliverNotification, args)
    Req.Test.stub(Slack, &Req.Test.json(&1, %{ok: false, error: "token_revoked"}))
    assert {:cancel, :unauthorized} = perform_job(DeliverNotification, args)
    Req.Test.stub(Slack, &Req.Test.json(&1, %{ok: false, error: "channel_not_found"}))
    assert {:cancel, :invalid_destination} = perform_job(DeliverNotification, args)
  end

  test "disconnect removes destinations and cancels pending jobs", ctx do
    args = job_args(ctx.check, alert_result_fixture(ctx.check))
    assert {:ok, _} = Notifications.disconnect(ctx.scope, ctx.team.id, "slack")
    assert Repo.all(Destination) == []
    assert {:cancel, :removed} = perform_job(DeliverNotification, args)
  end

  test "switching workspaces clears routes and cancels old jobs", ctx do
    args = job_args(ctx.check, alert_result_fixture(ctx.check))
    replacement = integration_fixture(ctx.scope, ctx.team, %{external_id: "TOTHER123"})
    assert replacement.id != ctx.integration.id
    assert Notifications.channels_for_check(ctx.check) == %{}
    assert {:cancel, :removed} = perform_job(DeliverNotification, args)
  end

  test "changing channels cancels pending jobs for the old channel", ctx do
    args = job_args(ctx.check, alert_result_fixture(ctx.check))

    {:ok, _} =
      Checks.update_check(ctx.scope, ctx.check, %{
        notification_channels: %{"slack" => "C87654321"}
      })

    assert {:cancel, :removed} = perform_job(DeliverNotification, args)
  end

  test "moving a server to another team stops delivery to the previous team", ctx do
    args = job_args(ctx.check, alert_result_fixture(ctx.check))
    team = team_fixture(ctx.scope)
    ctx.server |> Ecto.Changeset.change(team_id: team.id) |> Repo.update!()
    assert {:cancel, :destination_changed} = perform_job(DeliverNotification, args)
    assert Notifications.channels_for_check(ctx.check) == %{}
    Notifications.enqueue_alert(ctx.check, alert_result_fixture(ctx.check))
    refute_enqueued(worker: DeliverNotification)
  end

  defp job_args(check, result) do
    destination = Repo.get_by!(Destination, check_id: check.id)
    %{destination_id: destination.id, check_result_id: result.id}
  end

  defp expect_chart_upload do
    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.getUploadURLExternal"

      Req.Test.json(conn, %{
        ok: true,
        file_id: "F12345678",
        upload_url: "https://files.slack.com/upload/v1/signed"
      })
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/upload/v1/signed"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = body
      Plug.Conn.send_resp(conn, 200, "OK")
    end)

    Req.Test.expect(Slack, fn conn ->
      assert conn.request_path == "/api/files.completeUploadExternal"
      Req.Test.json(conn, %{ok: true})
    end)
  end
end
