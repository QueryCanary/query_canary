defmodule QueryCanary.ChecksTest.FakeConnectionServer do
  use GenServer

  @default_reply {:ok,
                  %{
                    rows: [%{"value" => 1}],
                    columns: ["value"],
                    num_rows: 1
                  }}

  def start_link(server_id, test_pid, reply \\ @default_reply) do
    GenServer.start_link(__MODULE__, {test_pid, reply},
      name: {:via, Registry, {QueryCanary.ConnectionRegistry, {:server, server_id}}}
    )
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:query, sql, params, opts}, _from, {test_pid, reply} = state) do
    send(test_pid, {:query_called, sql, params, opts})
    {:reply, reply, state}
  end
end

defmodule QueryCanary.ChecksTest do
  use QueryCanary.DataCase

  alias QueryCanary.Checks
  alias QueryCanary.Checks.Check
  alias QueryCanary.Checks.CheckResult
  alias QueryCanary.Accounts
  alias QueryCanary.Jobs.CheckRunner

  import QueryCanary.AccountsFixtures, only: [team_fixture: 1, user_scope_fixture: 0]
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

    test "get_check!/2 returns a team check for a team member" do
      owner_scope = user_scope_fixture()
      team = team_fixture(owner_scope)
      member_scope = add_team_member(owner_scope, team)
      server = server_fixture(owner_scope, %{team_id: team.id})
      check = check_fixture(owner_scope, %{server_id: server.id})

      assert Checks.get_check!(member_scope, check.id).id == check.id
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

    test "update_check/3 allows a team member to update a check they did not create" do
      owner_scope = user_scope_fixture()
      team = team_fixture(owner_scope)
      member_scope = add_team_member(owner_scope, team)
      server = server_fixture(owner_scope, %{team_id: team.id})
      check = check_fixture(owner_scope, %{server_id: server.id})

      assert {:ok, %Check{} = check} =
               Checks.update_check(member_scope, check, %{query: "some updated query"})

      assert check.query == "some updated query"
      assert check.user_id == owner_scope.user.id
    end

    test "update_check/3 rejects changing a check's server" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      check = check_fixture(scope)
      other_server = server_fixture(other_scope)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Checks.update_check(scope, check, %{server_id: other_server.id})

      assert {"cannot be changed after creation", _} = changeset.errors[:server_id]
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

    test "delete_check/2 allows a team member to delete a check they did not create" do
      owner_scope = user_scope_fixture()
      team = team_fixture(owner_scope)
      member_scope = add_team_member(owner_scope, team)
      server = server_fixture(owner_scope, %{team_id: team.id})
      check = check_fixture(owner_scope, %{server_id: server.id})

      assert {:ok, %Check{}} = Checks.delete_check(member_scope, check)
      assert_raise Ecto.NoResultsError, fn -> Checks.get_check!(owner_scope, check.id) end
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

    test "change_check/2 allows a team member to edit a check they did not create" do
      owner_scope = user_scope_fixture()
      team = team_fixture(owner_scope)
      member_scope = add_team_member(owner_scope, team)
      server = server_fixture(owner_scope, %{team_id: team.id})
      check = check_fixture(owner_scope, %{server_id: server.id})

      assert %Ecto.Changeset{} = Checks.change_check(member_scope, check)
    end

    test "run_check/1 gives checks a 30 second query timeout" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      check = check_fixture(scope, %{server_id: server.id, query: "SELECT 1"})

      {:ok, pid} = QueryCanary.ChecksTest.FakeConnectionServer.start_link(server.id, self())
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, %CheckResult{} = result} = Checks.run_check(check)
      assert result.success == true
      assert_receive {:query_called, "SELECT 1", [], opts}
      assert Keyword.fetch!(opts, :timeout) == 30_000
    end

    test "run_check/1 persists failed query results" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      check = check_fixture(scope, %{server_id: server.id, query: "SELECT count(*) FROM users"})

      {:ok, pid} =
        QueryCanary.ChecksTest.FakeConnectionServer.start_link(
          server.id,
          self(),
          {:error, "permission denied for table users"}
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, %CheckResult{} = result} = Checks.run_check(check)
      assert result.success == false
      assert result.result == []
      assert result.error == "permission denied for table users"
      assert_receive {:query_called, "SELECT count(*) FROM users", [], _opts}
    end

    test "CheckRunner returns an error when a check cannot be run" do
      scope = user_scope_fixture()
      check = check_fixture(scope, %{enabled: false})

      assert {:error, :disabled} = CheckRunner.perform(%Oban.Job{args: %{"id" => check.id}})
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

  defp add_team_member(owner_scope, team) do
    member_scope = user_scope_fixture()

    {:ok, _user} = Accounts.invite_user_to_team(owner_scope, team, member_scope.user.email)
    {:ok, _team_user} = Accounts.accept_team_invite(member_scope, team)

    member_scope
  end
end
