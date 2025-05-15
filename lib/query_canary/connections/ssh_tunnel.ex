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
      * :password - SSH password (optional)
      * :private_key - SSH private key (optional)
    * target_opts - Target connection to tunnel to
      * :host - Target hostname (from SSH server perspective)
      * :port - Target port
    * local_port - Local port to forward from

  ## Returns
    * {:ok, tunnel_ref} - Tunnel successfully created
    * {:error, reason} - Failed to create tunnel
  """
  def start_tunnel(ssh_opts, target_opts, local_port) do
    Logger.info("Starting SSH tunnel to #{ssh_opts.host}:#{ssh_opts.port}")

    # Determine authentication method
    ssh_connection_opts = [
      {:user, String.to_charlist(ssh_opts.user)},
      {:port, ssh_opts.port},
      {:silently_accept_hosts, true}
    ]

    # Add appropriate auth method
    auth_opts =
      cond do
        not is_nil(ssh_opts.password) ->
          [{:password, String.to_charlist(ssh_opts.password)}]

        not is_nil(ssh_opts.private_key) ->
          [{:key_cb, {SSHTunnelKeyProvider, private_key: ssh_opts.private_key}}]

        true ->
          []
      end

    ssh_connection_opts = ssh_connection_opts ++ auth_opts

    # Start the SSH connection
    case :ssh.connect(String.to_charlist(ssh_opts.host), ssh_opts.port, ssh_connection_opts) do
      {:ok, conn} ->
        # Set up the port forwarding
        case :ssh.tcpip_tunnel_from_server(
               conn,
               'localhost',
               local_port,
               String.to_charlist(target_opts.host),
               target_opts.port
             ) do
          {:ok, channel_id} ->
            Logger.info(
              "SSH tunnel established, forwarding localhost:#{local_port} to #{target_opts.host}:#{target_opts.port}"
            )

            {:ok, {conn, channel_id}}

          {:error, reason} ->
            :ssh.close(conn)
            Logger.error("Failed to create tunnel: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to connect to SSH server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops an SSH tunnel.

  ## Parameters
    * tunnel_ref - Reference to the tunnel returned by start_tunnel
  """
  def stop_tunnel({conn, channel_id}) do
    :ssh_connection.close(conn, channel_id)
    :ssh.close(conn)
    :ok
  end
end

# SSH Key provider for private key authentication
defmodule SSHTunnelKeyProvider do
  @behaviour :ssh_client_key_api

  def host_key(_algorithm, _host, _port, _key_fingerprint, _callback_data, _ssh_opts) do
    :accept_once
  end

  def is_host_key(_key, _host, _algorithm, _ssh_opts) do
    :accept_once
  end

  def sign_data(_algorithm, _data, _key, _opts) do
    {:error, :not_implemented}
  end

  def add_host_key(_host, _port, _pubkey_bin, _fingerprint, _ssh_opts) do
    :ok
  end
end
