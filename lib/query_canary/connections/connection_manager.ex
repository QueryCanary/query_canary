defmodule QueryCanary.Connections.ConnectionManager do
  @moduledoc """
  Manages database connections with support for different engines and SSH tunneling.

  Refactored to use persistent per-server ConnectionServer processes.
  """

  require Logger

  alias QueryCanary.Servers.Server
  alias QueryCanary.Connections.ConnectionServer

  @doc """
  Tests a database connection with optional SSH tunneling.

  ## Parameters
    * server - The database server configuration

  ## Returns
    * {:ok, connection_info} - Connection successful
    * {:error, reason} - Connection failed with reason
  """
  def test_connection(%Server{} = server) do
    with {:ok, _pid} <- ConnectionServer.ensure_started(server),
         {:ok, _} <- ConnectionServer.query(server.id, "SELECT 1") do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  @doc """
  Runs a query on the specified database server.

  ## Parameters
    * server - The database server configuration
    * query - The SQL query to execute
    * params - Query parameters (optional)

  ## Returns
    * {:ok, results} - Query executed successfully
    * {:error, reason} - Query failed with reason
  """
  def run_query(%Server{} = server, query, params \\ []) do
    with {:ok, _pid} <- ConnectionServer.ensure_started(server),
         reply <- ConnectionServer.query(server.id, query, params) do
      reply
    end
  end

  @doc """
  Lists tables in the connected database.

  ## Parameters
    * server - The database server configuration

  ## Returns
    * {:ok, tables} - List of tables in the database
    * {:error, reason} - Operation failed with reason
  """
  def list_tables(%Server{} = server) do
    with {:ok, _pid} <- ConnectionServer.ensure_started(server) do
      ConnectionServer.list_tables(server.id)
    end
  end

  @doc """
  Gets table schema for a specific table.

  ## Parameters
    * server - The database server configuration
    * table_name - The table name to get schema for

  ## Returns
    * {:ok, schema} - Schema information
    * {:error, reason} - Operation failed with reason
  """
  def get_database_schema(%Server{} = server) do
    with {:ok, _pid} <- ConnectionServer.ensure_started(server) do
      ConnectionServer.get_database_schema(server.id)
    end
  end
end
