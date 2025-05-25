defmodule QueryCanary.ChecksTest do
  use QueryCanary.DataCase

  alias QueryCanary.Checks
  alias QueryCanary.Checks.Check

  import QueryCanary.AccountsFixtures, only: [user_scope_fixture: 0]
  import QueryCanary.ChecksFixtures
  import QueryCanary.ServersFixtures

  @invalid_attrs %{name: nil, query: nil}

  describe "checks" do
    test "list_checks/1 returns all scoped checks" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      check = check_fixture(scope)
      other_check = check_fixture(other_scope)
      assert Enum.map(Checks.list_checks(scope), fn x -> x.id end) == [check.id]
      assert Enum.map(Checks.list_checks(other_scope), fn x -> x.id end) == [other_check.id]
    end

    test "get_check!/2 returns the check with given id" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      other_scope = user_scope_fixture()
      assert Checks.get_check!(scope, check.id).id == check.id
      assert_raise Ecto.NoResultsError, fn -> Checks.get_check!(other_scope, check.id) end
    end

    test "create_check/2 with valid data creates a check" do
      scope = user_scope_fixture()
      server = server_fixture(scope)

      valid_attrs = %{
        name: "some test query",
        query: "some query",
        schedule: "* * * * *",
        server_id: server.id
      }

      assert {:ok, %Check{} = check} = Checks.create_check(scope, valid_attrs)
      assert check.name == "some test query"
      assert check.query == "some query"
      assert check.schedule == "* * * * *"
      assert check.user_id == scope.user.id
    end

    test "create_check/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Checks.create_check(scope, @invalid_attrs)
    end

    test "update_check/3 with valid data updates the check" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      update_attrs = %{query: "some updated query"}

      assert {:ok, %Check{} = check} = Checks.update_check(scope, check, update_attrs)
      assert check.query == "some updated query"
    end

    test "update_check/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      check = check_fixture(scope)

      assert_raise MatchError, fn ->
        Checks.update_check(other_scope, check, %{})
      end
    end

    test "update_check/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Checks.update_check(scope, check, @invalid_attrs)
      assert check.id == Checks.get_check!(scope, check.id).id
    end

    test "delete_check/2 deletes the check" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      assert {:ok, %Check{}} = Checks.delete_check(scope, check)
      assert_raise Ecto.NoResultsError, fn -> Checks.get_check!(scope, check.id) end
    end

    test "delete_check/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      check = check_fixture(scope)
      assert_raise MatchError, fn -> Checks.delete_check(other_scope, check) end
    end

    test "change_check/2 returns a check changeset" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      assert %Ecto.Changeset{} = Checks.change_check(scope, check)
    end

    # test "run_check/1 executes a check and saves the result" do
    #   scope = user_scope_fixture()
    #   server = server_fixture(scope)
    #   check = check_fixture(scope, %{server_id: server.id, query: "SELECT 1"})

    #   assert {:ok, %CheckResult{} = result} = Checks.run_check(check)
    #   assert result.success == true
    #   assert result.result == [[1]]
    #   assert result.check_id == check.id
    # end

    # test "list_checks_with_status/1 returns checks with status information" do
    #   scope = user_scope_fixture()
    #   check = check_fixture(scope)

    #   # Simulate a check result
    #   {:ok, _result} = Checks.run_check(check)

    #   checks_with_status = Checks.list_checks_with_status(scope)
    #   assert length(checks_with_status) == 1

    #   check_with_status = hd(checks_with_status)
    #   assert check_with_status.last_result != nil
    #   assert check_with_status.last_run_at != nil
    # end

    # test "maybe_send_check_notification/2 sends notification for alerts" do
    #   scope = user_scope_fixture()
    #   server = server_fixture(scope)
    #   check = check_fixture(scope, %{server_id: server.id, query: "SELECT 1"})

    #   # Simulate a check result with an alert
    #   {:ok, result} = Checks.run_check(check)
    #   result = %{result | is_alert: true}

    #   assert {:ok, :notification_sent} = Checks.maybe_send_check_notification(check, result)
    # end
  end
end
