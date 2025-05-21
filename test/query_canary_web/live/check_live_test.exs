defmodule QueryCanaryWeb.CheckLiveTest do
  use QueryCanaryWeb.ConnCase

  import Phoenix.LiveViewTest
  import QueryCanary.ChecksFixtures

  @update_attrs %{
    name: "Updated Check",
    query: "some updated query",
    enabled: false,
    schedule: "0 0 * * *"
  }
  @invalid_attrs %{name: "", query: "", schedule: ""}

  setup :register_and_log_in_user

  defp create_check(%{scope: scope}) do
    check = check_fixture(scope)
    %{check: check}
  end

  describe "Index" do
    setup [:create_check]

    test "lists all checks", %{conn: conn, check: check} do
      {:ok, _index_live, html} = live(conn, ~p"/checks")

      assert html =~ "Database Checks"
      assert html =~ check.name
      assert html =~ check.query
    end

    test "updates check in listing", %{conn: conn, check: check} do
      {:ok, index_live, _html} = live(conn, ~p"/checks")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#checks-#{check.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/checks/#{check}/edit")

      assert render(form_live) =~ "Edit Check"

      assert form_live
             |> form("#check-form", check: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#check-form", check: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/checks")

      html = render(index_live)
      assert html =~ "Check updated successfully"
      assert html =~ "Updated Check"
      assert html =~ "some updated query"
    end

    test "deletes check in listing", %{conn: conn, check: check} do
      {:ok, index_live, _html} = live(conn, ~p"/checks")

      assert index_live |> element("#checks-#{check.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#checks-#{check.id}")
    end
  end

  describe "Show" do
    setup [:create_check]

    test "displays check", %{conn: conn, check: check} do
      {:ok, _show_live, html} = live(conn, ~p"/checks/#{check}")

      assert html =~ "Last run"
      assert html =~ check.name
      assert html =~ check.query
    end

    test "updates check and returns to show", %{conn: conn, check: check} do
      {:ok, show_live, _html} = live(conn, ~p"/checks/#{check}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/checks/#{check}/edit?return_to=show")

      assert render(form_live) =~ "Edit Check"

      assert form_live
             |> form("#check-form", check: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#check-form", check: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/checks/#{check}")

      html = render(show_live)
      assert html =~ "Check updated successfully"
      assert html =~ "Updated Check"
      assert html =~ "some updated query"
    end
  end
end
