defmodule QueryCanaryWeb.TeamLiveTest do
  use QueryCanaryWeb.ConnCase

  alias QueryCanary.Accounts

  import Phoenix.LiveViewTest
  import QueryCanary.AccountsFixtures

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  setup :register_and_log_in_user

  defp create_team(%{scope: scope}) do
    team = team_fixture(scope)

    %{team: team}
  end

  describe "Index" do
    setup [:create_team]

    test "lists all teams", %{conn: conn, team: team} do
      {:ok, _index_live, html} = live(conn, ~p"/teams")

      assert html =~ "Listing Teams"
      assert html =~ team.name
    end

    test "saves new team", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/teams")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Team")
               |> render_click()
               |> follow_redirect(conn, ~p"/teams/new")

      assert render(form_live) =~ "New Team"

      assert form_live
             |> form("#team-form", team: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#team-form", team: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Team created successfully"
      assert html =~ "some name"
    end

    test "updates team in listing", %{conn: conn, team: team} do
      {:ok, index_live, _html} = live(conn, ~p"/teams")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#teams-#{team.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/teams/#{team}/edit")

      assert render(form_live) =~ "Edit Team"

      assert form_live
             |> form("#team-form", team: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#team-form", team: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams")

      html = render(index_live)
      assert html =~ "Team updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes team in listing", %{conn: conn, team: team} do
      {:ok, index_live, _html} = live(conn, ~p"/teams")

      assert index_live |> element("#teams-#{team.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#teams-#{team.id}")
    end
  end

  describe "Show" do
    setup [:create_team]

    test "displays team", %{conn: conn, team: team} do
      {:ok, _show_live, html} = live(conn, ~p"/teams/#{team}")

      assert html =~ "Show Team"
      assert html =~ team.name
    end

    test "updates team and returns to show", %{conn: conn, team: team} do
      {:ok, show_live, _html} = live(conn, ~p"/teams/#{team}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/teams/#{team}/edit?return_to=show")

      assert render(form_live) =~ "Edit Team"

      assert form_live
             |> form("#team-form", team: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#team-form", team: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/teams/#{team}")

      html = render(show_live)
      assert html =~ "Team updated successfully"
      assert html =~ "some updated name"
    end

    test "admin changes an accepted member's role", %{conn: conn, scope: scope, team: team} do
      member = user_scope_fixture()
      {:ok, _} = Accounts.invite_user_to_team(scope, team, member.user.email)
      {:ok, _} = Accounts.accept_team_invite(member, team)

      {:ok, view, _} = live(conn, ~p"/teams/#{team}")

      assert view
             |> form("#role-form-#{member.user.id}", membership: %{role: "admin"})
             |> render_change() =~ "Role updated."

      assert Accounts.user_has_access_to_team?(member.user.id, team.id, :admin)

      assert view
             |> form("#role-form-#{member.user.id}", membership: %{role: "member"})
             |> render_change() =~ "Role updated."

      assert Accounts.user_has_access_to_team?(member.user.id, team.id, :member)
    end

    test "last admin sees why they cannot demote themselves", %{
      conn: conn,
      scope: scope,
      team: team
    } do
      {:ok, view, _} = live(conn, ~p"/teams/#{team}")

      assert view
             |> form("#role-form-#{scope.user.id}", membership: %{role: "member"})
             |> render_change() =~ "A team must have at least one admin."

      assert Accounts.user_has_access_to_team?(scope.user.id, team.id, :admin)
    end

    test "member cannot change roles through a forged event", %{scope: scope, team: team} do
      member = user_scope_fixture()
      {:ok, _} = Accounts.invite_user_to_team(scope, team, member.user.email)
      {:ok, _} = Accounts.accept_team_invite(member, team)
      conn = build_conn() |> log_in_user(member.user)

      {:ok, view, _} = live(conn, ~p"/teams/#{team}")
      refute has_element?(view, "#role-form-#{scope.user.id}")

      assert render_hook(view, "change_role", %{
               "membership" => %{"user_id" => scope.user.id, "role" => "member"}
             }) =~ "Only team admins can change roles."

      assert Accounts.user_has_access_to_team?(scope.user.id, team.id, :admin)
    end
  end
end
