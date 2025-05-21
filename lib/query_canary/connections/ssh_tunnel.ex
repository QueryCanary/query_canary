defmodule QueryCanary.Connections.SSHTunnel do
  @moduledoc """
  Provides SSH tunneling capabilities for secure database connections.

  This module manages the lifecycle of an SSH tunnel, creating a secure
  connection to a remote server and forwarding a local port to a target
  database port on the remote server.
  """

  require Logger

  @doc """
  Starts an SSH tunnel.

  ## Parameters
    * ssh_opts - SSH connection options
      * :host - SSH server hostname
      * :port - SSH server port
      * :user - SSH username
      * :private_key - SSH private key
    * target_opts - Target connection to tunnel to
      * :host - Target hostname (from SSH server perspective)
      * :port - Target port

  ## Returns
    * {:ok, tunnel_ref} - Tunnel successfully created
    * {:error, reason} - Failed to create tunnel
  """
  def start_tunnel(ssh_opts, target_opts) do
    Logger.info("Starting SSH tunnel to #{ssh_opts.host}:#{ssh_opts.port}")

    # Determine authentication method
    ssh_connection_opts = [
      {:user, String.to_charlist(ssh_opts.user)},
      {:silently_accept_hosts, true},
      # Add timeout for clearer error messages
      {:connect_timeout, 10000}
    ]

    # Add appropriate auth method
    auth_opts =
      cond do
        not is_nil(ssh_opts.private_key) and ssh_opts.private_key != "" ->
          [{:key_cb, {SSHTunnelKeyProvider, [{:private_key, ssh_opts.private_key}]}}]

        true ->
          # Try default key location if no explicit auth provided
          []
      end

    ssh_connection_opts = ssh_connection_opts ++ auth_opts

    # Start the SSH connection
    case :ssh.connect(String.to_charlist(ssh_opts.host), ssh_opts.port, ssh_connection_opts) do
      {:ok, conn} ->
        # Set up the port forwarding - CHANGED to tcpip_tunnel_to_server
        case :ssh.tcpip_tunnel_to_server(
               conn,
               {127, 0, 0, 1},
               0,
               String.to_charlist(target_opts.host),
               target_opts.port
             ) do
          {:ok, local_port} ->
            Logger.info(
              "SSH tunnel established, forwarding localhost:#{local_port} to #{target_opts.host}:#{target_opts.port}"
            )

            {:ok, {conn, local_port}}

          {:error, reason} ->
            :ssh.close(conn)
            Logger.error("Failed to create tunnel: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to connect to SSH server: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception occurred during SSH tunnel setup: #{inspect(e)}")
      {:error, "SSH tunnel exception: #{inspect(e)}"}
  end

  @doc """
  Stops an SSH tunnel.

  ## Parameters
    * tunnel_ref - Reference to the tunnel returned by start_tunnel
  """
  def stop_tunnel({conn, local_port}) do
    :ssh_connection.close(conn, local_port)
    :ssh.close(conn)
    :ok
  end
end

# SSH Key provider for private key authentication
defmodule SSHTunnelKeyProvider do
  @behaviour :ssh_client_key_api

  def add_host_key(_hostnames, _key, _connect_opts) do
    :ok
  end

  # credo:disable-for-next-line
  def is_host_key(_key, _host, _algorithm, _connect_opts) do
    true
  end

  def user_key(_algorithm, options) do
    try do
      key =
        Keyword.get(options, :key_cb_private)
        |> Keyword.get(:private_key)
        |> :public_key.pem_decode()
        |> List.first()
        |> :public_key.pem_entry_decode()

      {:ok, key}
    rescue
      e ->
        require Logger
        Logger.error("Failed to load SSH key: #{inspect(e)}")
        {:error, :bad_key}
    end
  end
end
