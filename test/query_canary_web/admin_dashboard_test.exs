defmodule QueryCanaryWeb.AdminDashboardTest do
  use QueryCanaryWeb.ConnCase

  import Phoenix.LiveViewTest
  import QueryCanary.AccountsFixtures

  alias QueryCanary.Accounts
  alias QueryCanary.Repo
  alias QueryCanaryWeb.UserAuth

  @dashboard_paths [
    "/admin/dashboard",
    "/admin/dashboard/home",
    "/admin/dashboard/nonode@nohost/metrics",
    "/admin/oban",
    "/admin/oban/jobs",
    "/admin/oban/jobs/1"
  ]

  setup context do
    if context[:oban_met] do
      # Manual testing mode skips the dashboard's metrics and connectivity processes.
      conf = Oban.config()
      start_supervised!({Oban.Met, conf: conf})

      start_supervised!(
        {Oban.Sonar,
         conf: %{conf | testing: :disabled}, name: Oban.Registry.via(Oban, Oban.Sonar)}
      )
    end

    :ok
  end

  describe "dashboard authorization" do
    test "requires login and preserves the requested path", %{conn: conn} do
      for path <- @dashboard_paths do
        response = get(conn, path)

        assert redirected_to(response) == ~p"/users/register"
        assert get_session(response, :user_return_to) == path
        assert response.halted
      end
    end

    test "rejects regular users, including team admins", %{conn: conn} do
      user = user_fixture()
      team_fixture(user_scope_fixture(user))
      conn = log_in_user(conn, user)

      for path <- @dashboard_paths do
        response = get(conn, path)

        assert redirected_to(response) == ~p"/"

        assert Phoenix.Flash.get(response.assigns.flash, :error) ==
                 "You must be an admin to access this page."

        assert response.halted
      end
    end

    test "admins can open Phoenix LiveDashboard", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      response = get(conn, ~p"/admin/dashboard")
      assert redirected_to(response) == ~p"/admin/dashboard/home"

      assert {:ok, _view, html} = live(conn, ~p"/admin/dashboard/home")
      assert html =~ "Phoenix LiveDashboard"
    end

    @tag :oban_met
    test "admins can open Oban Web", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      assert {:ok, _view, html} = live(conn, ~p"/admin/oban")
      assert html =~ "Oban"
    end

    @tag :oban_met
    test "revoking admin access between the page request and socket mount blocks both dashboards",
         %{
           conn: conn
         } do
      for path <- [~p"/admin/dashboard/home", ~p"/admin/oban"] do
        user = admin_fixture()
        response = conn |> log_in_user(user) |> get(path)
        assert html_response(response, 200)

        user |> Ecto.Changeset.change(is_admin: false) |> Repo.update!()

        assert {:error, {:redirect, %{to: "/"}}} = live(response)
      end
    end
  end

  describe "admin mount hook" do
    test "rejects missing, invalid, and deleted session tokens" do
      token = Accounts.generate_user_session_token(admin_fixture())
      Accounts.delete_user_session_token(token)

      for session <- [%{}, %{"user_token" => "invalid"}, %{"user_token" => token}] do
        assert {:halt, socket} =
                 UserAuth.on_mount(:require_admin, %{}, session, socket())

        assert {:redirect, %{to: "/users/register"}} = socket.redirected
      end
    end

    test "rejects valid sessions belonging to non-admins" do
      token = Accounts.generate_user_session_token(user_fixture())

      assert {:halt, socket} =
               UserAuth.on_mount(:require_admin, %{}, %{"user_token" => token}, socket())

      assert {:redirect, %{to: "/"}} = socket.redirected
    end
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      endpoint: QueryCanaryWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end
end
