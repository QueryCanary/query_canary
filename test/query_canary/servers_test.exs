defmodule QueryCanary.ServersTest do
  use QueryCanary.DataCase

  alias QueryCanary.Servers

  describe "servers" do
    alias QueryCanary.Servers.Server

    import QueryCanary.AccountsFixtures, only: [user_scope_fixture: 0]
    import QueryCanary.ServersFixtures

    @invalid_attrs %{
      db_port: nil,
      db_hostname: nil,
      db_username: nil,
      db_password: nil,
      db_name: nil
    }

    test "list_servers/1 returns all scoped servers" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      server = server_fixture(scope)
      other_server = server_fixture(other_scope)
      assert Enum.map(Servers.list_servers(scope), fn x -> x.id end) == [server.id]
      assert Enum.map(Servers.list_servers(other_scope), fn x -> x.id end) == [other_server.id]
    end

    test "get_server!/2 returns the server with given id" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      other_scope = user_scope_fixture()
      assert Servers.get_server!(scope, server.id).id == server.id
      assert_raise Ecto.NoResultsError, fn -> Servers.get_server!(other_scope, server.id) end
    end

    test "create_server/2 with valid data creates a server" do
      valid_attrs = %{
        name: "Foo Test",
        db_engine: "sqlite",
        db_port: 42,
        db_hostname: "some hostname",
        db_username: "some username",
        db_password_input: "some password",
        db_name: "some database"
      }

      scope = user_scope_fixture()

      assert {:ok, %Server{} = server} = Servers.create_server(scope, valid_attrs)
      assert server.db_port == 42
      assert server.db_hostname == "some hostname"
      assert server.db_username == "some username"
      assert String.starts_with?(server.db_password, "XCP.")
      assert server.db_name == "some database"
      assert server.user_id == scope.user.id
    end

    test "create_server/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Servers.create_server(scope, @invalid_attrs)
    end

    test "update_server/3 with valid data updates the server" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      old_server = server

      update_attrs = %{
        db_port: 43,
        db_hostname: "some updated hostname",
        db_username: "some updated username",
        db_password_input: "some updated password",
        db_name: "some updated database"
      }

      assert {:ok, %Server{} = server} = Servers.update_server(scope, server, update_attrs)
      assert server.db_port == 43
      assert server.db_hostname == "some updated hostname"
      assert server.db_username == "some updated username"
      assert server.db_name == "some updated database"
      assert String.starts_with?(server.db_password, "XCP.")
      refute server.db_password == old_server.db_password
    end

    test "update_server/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      server = server_fixture(scope)

      assert_raise AccessError, fn ->
        Servers.update_server(other_scope, server, %{})
      end
    end

    test "update_server/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Servers.update_server(scope, server, @invalid_attrs)
      assert server.id == Servers.get_server!(scope, server.id).id
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
      assert_raise AccessError, fn -> Servers.delete_server(other_scope, server) end
    end

    test "change_server/2 returns a server changeset" do
      scope = user_scope_fixture()
      server = server_fixture(scope)
      assert %Ecto.Changeset{} = Servers.change_server(scope, server)
    end
  end
end
