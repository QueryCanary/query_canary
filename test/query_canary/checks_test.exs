defmodule QueryCanary.ChecksTest do
  use QueryCanary.DataCase

  alias QueryCanary.Checks

  describe "checks" do
    alias QueryCanary.Checks.Check

    import QueryCanary.AccountsFixtures, only: [user_scope_fixture: 0]
    import QueryCanary.ChecksFixtures

    @invalid_attrs %{query: nil, expectation: nil}

    test "list_checks/1 returns all scoped checks" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      check = check_fixture(scope)
      other_check = check_fixture(other_scope)
      assert Checks.list_checks(scope) == [check]
      assert Checks.list_checks(other_scope) == [other_check]
    end

    test "get_check!/2 returns the check with given id" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      other_scope = user_scope_fixture()
      assert Checks.get_check!(scope, check.id) == check
      assert_raise Ecto.NoResultsError, fn -> Checks.get_check!(other_scope, check.id) end
    end

    test "create_check/2 with valid data creates a check" do
      valid_attrs = %{query: "some query", expectation: "some expectation"}
      scope = user_scope_fixture()

      assert {:ok, %Check{} = check} = Checks.create_check(scope, valid_attrs)
      assert check.query == "some query"
      assert check.expectation == "some expectation"
      assert check.user_id == scope.user.id
    end

    test "create_check/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Checks.create_check(scope, @invalid_attrs)
    end

    test "update_check/3 with valid data updates the check" do
      scope = user_scope_fixture()
      check = check_fixture(scope)
      update_attrs = %{query: "some updated query", expectation: "some updated expectation"}

      assert {:ok, %Check{} = check} = Checks.update_check(scope, check, update_attrs)
      assert check.query == "some updated query"
      assert check.expectation == "some updated expectation"
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
      assert check == Checks.get_check!(scope, check.id)
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
  end
end
