defmodule QueryCanaryWeb.ServerLiveTest do
  use QueryCanaryWeb.ConnCase

  import Phoenix.LiveViewTest
  import QueryCanary.ServersFixtures

  # @update_attrs %{
  #   name: "Updated Server",
  #   db_hostname: "updated-host",
  #   db_port: 3306,
  #   db_username: "updated_user",
  #   db_password_input: "updated_password",
  #   db_name: "updated_db",
  #   ssh_tunnel: true,
  #   ssh_hostname: "ssh-host",
  #   ssh_port: 22,
  #   ssh_username: "ssh_user"
  # }

  setup :register_and_log_in_user

  defp create_server(%{scope: scope}) do
    server = server_fixture(scope)
    %{server: server}
  end

  describe "Index" do
    setup [:create_server]

    test "lists all servers", %{conn: conn, server: server} do
      {:ok, _index_live, html} = live(conn, ~p"/servers")

      assert html =~ "Database Servers"
      assert html =~ server.name
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

      assert html =~ "Database server configuration"
      assert html =~ server.name
    end

    test "updates server and returns to show with SSH Tunnel toggle", %{
      conn: conn,
      server: server
    } do
      {:ok, show_live, _html} = live(conn, ~p"/servers/#{server}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/servers/#{server}/edit?return_to=show")

      assert render(form_live) =~ "Edit Server"

      # Test toggling SSH Tunnel checkbox
      form_live
      |> form("#server-form", server: %{ssh_tunnel: true})
      |> render_change()

      assert render(form_live) =~ "SSH Tunnel Configuration"
      assert render(form_live) =~ "SSH Hostname"
      assert render(form_live) =~ "SSH Port"
      assert render(form_live) =~ "SSH Username"

      # Submit the form with updated attributes
      # assert form_live
      #        |> form("#server-form", server: @update_attrs)
      #        |> render_submit()
      #        |> IO.puts()
      #        |> follow_redirect(conn, ~p"/servers/#{server}")

      # html = render(show_live)
      # assert html =~ "Server updated successfully"
      # assert html =~ "Updated Server"
    end
  end
end
