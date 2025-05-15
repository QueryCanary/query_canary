defmodule QueryCanaryWeb.ServerLiveTest do
  use QueryCanaryWeb.ConnCase

  import Phoenix.LiveViewTest
  import QueryCanary.ServersFixtures

  @create_attrs %{port: 42, hostname: "some hostname", username: "some username", password: "some password", database: "some database"}
  @update_attrs %{port: 43, hostname: "some updated hostname", username: "some updated username", password: "some updated password", database: "some updated database"}
  @invalid_attrs %{port: nil, hostname: nil, username: nil, password: nil, database: nil}

  setup :register_and_log_in_user

  defp create_server(%{scope: scope}) do
    server = server_fixture(scope)

    %{server: server}
  end

  describe "Index" do
    setup [:create_server]

    test "lists all servers", %{conn: conn, server: server} do
      {:ok, _index_live, html} = live(conn, ~p"/servers")

      assert html =~ "Listing Servers"
      assert html =~ server.hostname
    end

    test "saves new server", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/servers")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Server")
               |> render_click()
               |> follow_redirect(conn, ~p"/servers/new")

      assert render(form_live) =~ "New Server"

      assert form_live
             |> form("#server-form", server: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#server-form", server: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/servers")

      html = render(index_live)
      assert html =~ "Server created successfully"
      assert html =~ "some hostname"
    end

    test "updates server in listing", %{conn: conn, server: server} do
      {:ok, index_live, _html} = live(conn, ~p"/servers")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#servers-#{server.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/servers/#{server}/edit")

      assert render(form_live) =~ "Edit Server"

      assert form_live
             |> form("#server-form", server: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#server-form", server: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/servers")

      html = render(index_live)
      assert html =~ "Server updated successfully"
      assert html =~ "some updated hostname"
    end

    test "deletes server in listing", %{conn: conn, server: server} do
      {:ok, index_live, _html} = live(conn, ~p"/servers")

      assert index_live |> element("#servers-#{server.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#servers-#{server.id}")
    end
  end

  describe "Show" do
    setup [:create_server]

    test "displays server", %{conn: conn, server: server} do
      {:ok, _show_live, html} = live(conn, ~p"/servers/#{server}")

      assert html =~ "Show Server"
      assert html =~ server.hostname
    end

    test "updates server and returns to show", %{conn: conn, server: server} do
      {:ok, show_live, _html} = live(conn, ~p"/servers/#{server}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/servers/#{server}/edit?return_to=show")

      assert render(form_live) =~ "Edit Server"

      assert form_live
             |> form("#server-form", server: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#server-form", server: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/servers/#{server}")

      html = render(show_live)
      assert html =~ "Server updated successfully"
      assert html =~ "some updated hostname"
    end
  end
end
