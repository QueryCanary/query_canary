defmodule QueryCanaryWeb.MongoDBQuickstartTest do
  use QueryCanaryWeb.ConnCase
  import Phoenix.LiveViewTest
  import QueryCanary.ServersFixtures
  setup :register_and_log_in_user

  test "quickstart enables MongoDB and sets connection defaults", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/quickstart")
    assert has_element?(view, "input[type=radio][value=mongodb]:not([disabled])")
    view |> form("#server-form", server: %{db_engine: "mongodb"}) |> render_change()
    assert has_element?(view, "#server_db_port[value='27017']")
    assert has_element?(view, "#server_db_auth_source")
    assert has_element?(view, "a[href='/docs/servers/mongodb']")
  end

  test "check editor uses JSON and starts with a count query", %{conn: conn, scope: scope} do
    server = server_fixture(scope, %{db_engine: "mongodb", db_port: 27017})
    {:ok, view, html} = live(conn, ~p"/quickstart/check?server_id=#{server.id}")
    assert html =~ "MongoDB JSON Query"
    assert has_element?(view, "[phx-hook=SQLEditor][data-dialect=mongodb]")
    assert has_element?(view, "input[name='check[query]'][value*='count']")
  end
end
