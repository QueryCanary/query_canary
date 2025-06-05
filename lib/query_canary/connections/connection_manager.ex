defmodule QueryCanary.Connections.ConnectionManager do
  @moduledoc """
  Manages database connections with support for different engines and SSH tunneling.

  This module provides an adapter pattern for interacting with various database engines
  while abstracting away the complexity of SSH tunneling and connection pooling.
  """

  alias QueryCanary.Servers.Server
  alias QueryCanary.Connections.SSHTunnel

  @doc """
  Tests a database connection with optional SSH tunneling.

  ## Parameters
    * server - The database server configuration

  ## Returns
    * {:ok, connection_info} - Connection successful
    * {:error, reason} - Connection failed with reason
  """
  def test_connection(%Server{} = server) do
    run_query(server, "SELECT NOW();")
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
    with {:ok, conn_details} <- prepare_connection(server),
         {:ok, conn} <- get_adapter(server).connect(conn_details),
         {:ok, results} <- get_adapter(server).query(conn, query, params) do
      {:ok, results}
    else
      {:error, reason} -> {:error, reason}
    end
  after
    # Always close any SSH tunnels that might have been opened
    cleanup_resources(server)
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
    with {:ok, conn_details} <- prepare_connection(server),
         {:ok, conn} <- get_adapter(server).connect(conn_details),
         {:ok, tables} <- get_adapter(server).list_tables(conn) do
      {:ok, tables}
    else
      {:error, reason} -> {:error, reason}
    end
  after
    cleanup_resources(server)
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
    with {:ok, conn_details} <- prepare_connection(server),
         {:ok, conn} <- get_adapter(server).connect(conn_details),
         {:ok, schema} <- get_adapter(server).get_database_schema(conn, server.db_name) do
      {:ok, schema}
    else
      {:error, reason} -> {:error, reason}
    end
  after
    cleanup_resources(server)
  end

  # Private functions

  # Sets up an SSH tunnel if enabled, and returns modified connection details
  defp prepare_connection(%Server{ssh_tunnel: true} = server) do
    # Decrypt any encrypted credentials from the server
    server = decrypt_credentials(server)

    ssh_opts = %{
      host: server.ssh_hostname,
      port: server.ssh_port,
      user: server.ssh_username,
      private_key: server.ssh_private_key
    }

    target_opts = %{
      host: server.db_hostname,
      port: server.db_port
    }

    case SSHTunnel.start_tunnel(ssh_opts, target_opts) do
      {:ok, {_conn, port} = tunnel_ref} ->
        # Store the tunnel reference in the process dictionary
        # so we can clean it up later
        Process.put(:ssh_tunnel_ref, tunnel_ref)

        # Return connection details that point to the local tunnel endpoint
        {:ok,
         %{
           hostname: "127.0.0.1",
           port: port,
           username: server.db_username,
           password: server.db_password,
           database: server.db_name,
           ssl: true,
           socket_options: []
         }}

      {:error, reason} ->
        {:error, "SSH tunnel failed: #{inspect(reason)}"}
    end
  end

  # Returns standard connection details for direct connections
  defp prepare_connection(%Server{} = server) do
    # Decrypt any encrypted credentials from the server
    server = decrypt_credentials(server)

    {:ok,
     %{
       hostname: server.db_hostname,
       port: server.db_port,
       username: server.db_username,
       password: server.db_password,
       database: server.db_name,
       ssl: true,
       socket_options: socket_options(server)
     }}
  end

  defp socket_options(%Server{} = server) do
    case :inet_res.gethostbyname(String.to_charlist(server.db_hostname), :inet6) do
      {:ok, {:hostent, _host, [], _, _, _}} ->
        [:inet6]

      _ ->
        []
    end
  end

  # Returns the appropriate database adapter module based on db_engine
  defp get_adapter(%Server{db_engine: "postgresql"}),
    do: QueryCanary.Connections.Adapters.PostgreSQL

  defp get_adapter(%Server{db_engine: "mysql"}),
    do: QueryCanary.Connections.Adapters.MySQL

  defp get_adapter(%Server{db_engine: "clickhouse"}),
    do: QueryCanary.Connections.Adapters.ClickHouse

  defp get_adapter(%Server{db_engine: engine}),
    do: raise("Unsupported database engine: #{engine}")

  # Clean up any resources like SSH tunnels
  # Clean up any resources like SSH tunnels and database connections
  defp cleanup_resources(_server) do
    # Clean up SSH tunnel if exists
    case Process.get(:ssh_tunnel_ref) do
      nil ->
        :ok

      tunnel_ref ->
        SSHTunnel.stop_tunnel(tunnel_ref)
        Process.delete(:ssh_tunnel_ref)
    end

    # Clean up database connection if exists
    case Process.get(:db_connection_pid) do
      nil ->
        :ok

      db_conn ->
        # Safely disconnect based on adapter type
        cond do
          is_pid(db_conn) and Process.alive?(db_conn) ->
            try do
              GenServer.stop(db_conn, :normal, 5000)
            catch
              _, _ -> :ok
            end

          true ->
            :ok
        end

        Process.delete(:db_connection_pid)
    end
  end

  # Decrypt sensitive credentials from the server
  defp decrypt_credentials(server) do
    %{
      server
      | db_password: decrypt_if_needed(server.db_password, "db_password"),
        ssh_private_key: decrypt_if_needed(server.ssh_private_key, "ssh_private_key")
    }
  end

  defp decrypt_if_needed(nil, _), do: nil

  defp decrypt_if_needed(encrypted, salt) do
    case Phoenix.Token.decrypt(QueryCanaryWeb.Endpoint, salt, encrypted, max_age: :infinity) do
      {:ok, decrypted} ->
        decrypted

      # Return as-is if we can't decrypt
      {:error, _} ->
        encrypted
    end
  end
end
