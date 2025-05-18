defmodule QueryCanary.Connections.ConnectionTester do
  @moduledoc """
  Provides comprehensive testing and diagnostic functionality for database connections.

  This module offers different levels of connection testing:
  1. DNS resolution checks
  2. Network connectivity tests
  3. Authentication verification
  4. Database access validation

  Each test returns detailed diagnostic information to help users troubleshoot connection issues.
  """

  alias QueryCanary.Servers.Server
  alias QueryCanary.Connections.ConnectionManager

  @doc """
  Performs a complete diagnostic test on a database connection.

  ## Parameters
    * server - The database server configuration

  ## Returns
    * {:ok, connection_info} - Connection successful with version details
    * {:error, %{type: error_type, message: message}} - Connection failed with categorized reason
  """
  def diagnose_connection(%Server{} = server) do
    # First, perform a hostname resolution test
    with {:ok, _} <- check_hostname(server),
         # Then verify network connectivity
         {:ok, _} <- check_port_connectivity(server),
         # If successful, get version information for confirmation
         {:ok, results} <-
           ConnectionManager.run_query(server, get_version_query(server)) do
      version = extract_version_info(results)

      {:ok,
       %{message: "Successfully connected to #{server.db_engine} database", version: version}}
    else
      {:error, %{type: _type, message: _message} = error} ->
        {:error, error}

      # Convert generic errors to specific diagnostic errors
      {:error, reason} when is_binary(reason) ->
        cond do
          String.contains?(reason, "authentication") or String.contains?(reason, "password") ->
            {:error, %{type: :auth_error, message: "Authentication failed: #{reason}"}}

          String.contains?(reason, "SSL") ->
            {:error, %{type: :ssl_error, message: "SSL connection issue: #{reason}"}}

          String.contains?(reason, "database") ->
            {:error, %{type: :database_error, message: "Database access error: #{reason}"}}

          {:error, reason} ->
            {:error, %{type: :unknown_error, message: "Connection failed: #{inspect(reason)}"}}
        end

      {:error, reason} ->
        {:error, %{type: :unknown_error, message: "Connection failed: #{inspect(reason)}"}}
    end
  end

  @doc """
  Checks if the hostname can be resolved.

  ## Returns
    * {:ok, :hostname_resolved} - Hostname resolved successfully
    * {:error, %{type: :dns_error, message: message}} - DNS resolution failed
  """
  def check_hostname(%Server{ssh_tunnel: true} = server) do
    # For SSH tunnels, we need to check the SSH hostname first
    case :inet.getaddr(String.to_charlist(server.ssh_hostname), :inet) do
      {:ok, _} ->
        {:ok, :hostname_resolved}

      {:error, reason} ->
        {:error,
         %{
           type: :dns_error,
           message:
             "Cannot resolve SSH hostname: #{server.ssh_hostname}. Error: #{inspect(reason)}"
         }}
    end
  end

  def check_hostname(%Server{} = server) do
    case :inet.getaddr(String.to_charlist(server.db_hostname), :inet) do
      {:ok, _} ->
        {:ok, :hostname_resolved}

      {:error, _reason} ->
        case :inet.getaddr(String.to_charlist(server.db_hostname), :inet6) do
          {:ok, _} ->
            {:ok, :hostname_resolved}

          {:error, _reason} ->
            {:error,
             %{
               type: :dns_error,
               message:
                 "Cannot resolve database hostname: #{server.db_hostname} into an IPv4 or IPv6 address."
             }}
        end
    end
  end

  @doc """
  Checks if the server port is accessible.

  ## Returns
    * {:ok, :port_accessible} - Port is accessible
    * {:error, %{type: :network_error, message: message}} - Network connectivity issue
  """
  def check_port_connectivity(%Server{ssh_tunnel: true} = server) do
    # For SSH tunnels, check SSH port accessibility first
    case :gen_tcp.connect(String.to_charlist(server.ssh_hostname), server.ssh_port, [], 5000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        {:ok, :port_accessible}

      {:error, reason} ->
        {:error,
         %{
           type: :network_error,
           message:
             "Cannot connect to SSH server port #{server.ssh_port} on #{server.ssh_hostname}. Error: #{inspect(reason)}"
         }}
    end
  end

  def check_port_connectivity(%Server{} = server) do
    case :gen_tcp.connect(String.to_charlist(server.db_hostname), server.db_port, [], 5000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        {:ok, :port_accessible}

      {:error, reason} ->
        {:error,
         %{
           type: :network_error,
           message:
             "Cannot connect to database port #{server.db_port} on #{server.db_hostname}. Error: #{inspect(reason)}"
         }}
    end
  end

  # Get appropriate version query based on DB engine
  defp get_version_query(%Server{db_engine: "postgresql"}), do: "SELECT version();"
  defp get_version_query(%Server{db_engine: "mysql"}), do: "SELECT VERSION();"
  defp get_version_query(%Server{db_engine: engine}), do: "SELECT 'Connected to #{engine}';"

  # Extract version information from query results based on DB engine
  defp extract_version_info(results) do
    try do
      case results do
        [[version]] when is_binary(version) -> version
        %{rows: [[version]]} when is_binary(version) -> version
        _ -> "Unknown version"
      end
    rescue
      _ -> "Version information unavailable"
    end
  end
end
