defmodule QueryCanary.ChecksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `QueryCanary.Checks` context.
  """

  alias QueryCanary.ServersFixtures

  @doc """
  Generate a check.
  """
  def check_fixture(scope, attrs \\ %{}) do
    # Create a server fixture if `server_id` is not provided
    server_id = Map.get(attrs, :server_id) || ServersFixtures.server_fixture(scope).id

    attrs =
      Enum.into(attrs, %{
        name: "Test Check",
        schedule: "* * * * *",
        enabled: true,
        query: "SELECT * FROM test_table",
        expectation: %{"key" => "value"},
        server_id: server_id
      })

    {:ok, check} = QueryCanary.Checks.create_check(scope, attrs)
    check
  end
end
