defmodule QueryCanaryWeb.QuickstartScheduleTest do
  use QueryCanaryWeb.ConnCase

  import Phoenix.LiveViewTest
  import QueryCanary.ServersFixtures

  setup :register_and_log_in_user

  test "quickstart previews a local daily schedule", %{conn: conn, scope: scope} do
    server = server_fixture(scope)
    {:ok, view, _} = live(conn, ~p"/quickstart/check?server_id=#{server.id}")

    assert has_element?(view, "#schedule-kind option[selected][value='daily']")

    html =
      view
      |> form("#check-form",
        schedule_ui: %{time: "14:15"},
        check: %{timezone: "Europe/London"}
      )
      |> render_change()

    assert html =~ "Every day at 2:15 PM (Europe/London)"
    assert html =~ "Next three runs"
  end
end
