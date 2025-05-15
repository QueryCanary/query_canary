defmodule QueryCanary.ServersTest do
  use QueryCanary.DataCase

  alias QueryCanary.Servers

  describe "servers" do
    alias QueryCanary.Servers.Server

    import QueryCanary.AccountsFixtures, only: [user_scope_fixture: 0]
    import QueryCanary.ServersFixtures

    @invalid_attrs %{port: nil, hostname: nil, username: nil, password: nil, database: nil}

    test "list_servers/1 returns all scoped servers" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      server = server_fixture(scope)
      other_server = server_fixture(other_scope)
      assert Servers.list_servers(scope) == [server]
      assert Servers.list_servers(other_scope) == [other_server]
    end

    test "get_server!/2 returns the server with given id" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      other_scope = user_scope_fixture()
      assert Servers.get_server!(scope, server.id) == server
      assert_raise Ecto.NoResultsError, fn -> Servers.get_server!(other_scope, server.id) end
    end

    test "create_server/2 with valid data creates a server" do
      valid_attrs = %{port: 42, hostname: "some hostname", username: "some username", password: "some password", database: "some database"}
      scope = user_scope_fixture()

      assert {:ok, %Server{} = server} = Servers.create_server(scope, valid_attrs)
      assert server.port == 42
      assert server.hostname == "some hostname"
      assert server.username == "some username"
      assert server.password == "some password"
      assert server.database == "some database"
      assert server.user_id == scope.user.id
    end

    test "create_server/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Servers.create_server(scope, @invalid_attrs)
    end

    test "update_server/3 with valid data updates the server" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      update_attrs = %{port: 43, hostname: "some updated hostname", username: "some updated username", password: "some updated password", database: "some updated database"}

      assert {:ok, %Server{} = server} = Servers.update_server(scope, server, update_attrs)
      assert server.port == 43
      assert server.hostname == "some updated hostname"
      assert server.username == "some updated username"
      assert server.password == "some updated password"
      assert server.database == "some updated database"
    end

    test "update_server/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      server = server_fixture(scope)

      assert_raise MatchError, fn ->
        Servers.update_server(other_scope, server, %{})
      end
    end

    test "update_server/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Servers.update_server(scope, server, @invalid_attrs)
      assert server == Servers.get_server!(scope, server.id)
    end

    test "delete_server/2 deletes the server" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      assert {:ok, %Server{}} = Servers.delete_server(scope, server)
      assert_raise Ecto.NoResultsError, fn -> Servers.get_server!(scope, server.id) end
    end

    test "delete_server/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      server = server_fixture(scope)
      assert_raise MatchError, fn -> Servers.delete_server(other_scope, server) end
    end

    test "change_server/2 returns a server changeset" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      assert %Ecto.Changeset{} = Servers.change_server(scope, server)
    end
  end
end
