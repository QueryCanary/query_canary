defmodule QueryCanary.ServersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `QueryCanary.Servers` context.
  """

  @doc """
  Generate a server.
  """
  def server_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Test Server",
        db_engine: "sqlite",
        db_hostname: "localhost",
        db_port: 5432,
        db_name: "test_db",
        db_username: "test_user",
        db_password_input: "test_password",
        ssh_tunnel: false,
        schema: %{}
      })

    {:ok, server} = QueryCanary.Servers.create_server(scope, attrs)
    server
  end
end
