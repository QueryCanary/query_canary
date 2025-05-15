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
        database: "some database",
        hostname: "some hostname",
        password: "some password",
        password: "some password",
        port: 42,
        username: "some username"
      })

    {:ok, server} = QueryCanary.Servers.create_server(scope, attrs)
    server
  end
end
