defmodule QueryCanary.Connections.ConnectionServer do
  @moduledoc """
  Persistent per-customer database connection process.

  Responsibilities:
    * Establish and maintain a single adapter connection
    * Optional auto-reconnect with backoff
    * Execute queries via adapter
    * Manage SSH tunnels lifecycle
    * Provide status/metadata
  """
  use GenServer
  require Logger

  alias QueryCanary.Servers.Server
  alias QueryCanary.Connections.SSHTunnel

  @type server_id :: any

  # Public API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via(opts[:server_id]))
  end

  def ensure_started(%Server{id: id} = server), do: ensure_started(id, server)

  def ensure_started(id, %Server{} = server) do
    case GenServer.whereis(via(id)) do
      nil -> DynamicSupervisor.start_child(QueryCanary.ConnectionSupervisor, child_spec(server))
      pid -> {:ok, pid}
    end
  end

  def query(server_id, sql, params \\ []) do
    GenServer.call(via(server_id), {:query, sql, params})
  end

  def list_tables(server_id), do: GenServer.call(via(server_id), :list_tables)
  def get_database_schema(server_id), do: GenServer.call(via(server_id), :get_database_schema)
  def status(server_id), do: GenServer.call(via(server_id), :status)
  def disconnect(server_id), do: GenServer.call(via(server_id), :disconnect)
  def refresh(server_id), do: GenServer.cast(via(server_id), :refresh)

  def child_spec(%Server{} = server) do
    %{
      id: {:connection_server, server.id},
      start: {__MODULE__, :start_link, [[server: server, server_id: server.id]]},
      restart: :transient,
      shutdown: 15_000,
      type: :worker
    }
  end

  # GenServer callbacks
  def init(opts) do
    server = Keyword.fetch!(opts, :server)

    state = %{
      server: server,
      server_id: server.id,
      adapter: adapter_for(server),
      adapter_conn: nil,
      tunnel_ref: nil,
      status: :starting,
      last_error: nil,
      auto_reconnect: Application.get_env(:query_canary, :connection_auto_reconnect, true),
      backoff: 500,
      max_backoff: 10_000
    }

    send(self(), :connect)
    {:ok, state}
  end

  def handle_info(:connect, state) do
    case establish(state.server, state.adapter) do
      {:ok, adapter_conn, tunnel_ref} ->
        Logger.metadata(server_id: state.server_id)
        Logger.info("Connection established to #{state.server_id}")

        {:noreply,
         %{
           state
           | adapter_conn: adapter_conn,
             tunnel_ref: tunnel_ref,
             status: :connected,
             last_error: nil,
             backoff: 500
         }}

      {:error, reason} ->
        Logger.warning("Connection failed: #{inspect(reason)} to #{state.server_id}")

        if state.auto_reconnect do
          Process.send_after(self(), :connect, state.backoff)
          next_backoff = min(state.backoff * 2, state.max_backoff)

          {:noreply,
           %{state | status: {:error, reason}, last_error: reason, backoff: next_backoff}}
        else
          {:noreply, %{state | status: {:error, reason}, last_error: reason}}
        end
    end
  end

  def handle_cast(:refresh, state) do
    cleanup(state)
    send(self(), :connect)
    {:noreply, %{state | status: :refreshing, adapter_conn: nil, tunnel_ref: nil}}
  end

  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  def handle_call(:disconnect, _from, state) do
    cleanup(state)
    {:reply, :ok, %{state | status: :disconnected, adapter_conn: nil, tunnel_ref: nil}}
  end

  def handle_call({:query, _sql, _params}, _from, %{status: status} = state)
      when status != :connected do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:query, sql, params}, _from, state) do
    reply = state.adapter.query(state.adapter_conn, sql, params)
    {:reply, reply, state}
  end

  def handle_call(:list_tables, _from, %{status: :connected} = state) do
    {:reply, state.adapter.list_tables(state.adapter_conn), state}
  end

  def handle_call(:list_tables, _from, state), do: {:reply, {:error, :not_connected}, state}

  def handle_call(:get_database_schema, _from, %{status: :connected, server: server} = state) do
    {:reply, state.adapter.get_database_schema(state.adapter_conn, server.db_name), state}
  end

  def handle_call(:get_database_schema, _from, state),
    do: {:reply, {:error, :not_connected}, state}

  def terminate(_reason, state) do
    cleanup(state)
    :ok
  end

  # Helpers
  defp establish(server, adapter) do
    with {:ok, conn_details, tunnel_ref} <- prepare(server),
         {:ok, adapter_conn} <- adapter.connect(conn_details) do
      {:ok, adapter_conn, tunnel_ref}
    end
  end

  defp prepare(%Server{ssh_tunnel: true} = server) do
    server = decrypt(server)

    ssh_opts = %{
      host: server.ssh_hostname,
      port: server.ssh_port,
      user: server.ssh_username,
      private_key: server.ssh_private_key
    }

    target_opts = %{host: server.db_hostname, port: server.db_port}

    case SSHTunnel.start_tunnel(ssh_opts, target_opts) do
      {:ok, {_conn, port} = ref} ->
        {:ok,
         base_conn_details(server) |> Map.put(:hostname, "127.0.0.1") |> Map.put(:port, port),
         ref}

      {:error, reason} ->
        {:error, {:ssh_tunnel_failed, reason}}
    end
  end

  defp prepare(%Server{} = server), do: {:ok, base_conn_details(decrypt(server)), nil}

  defp base_conn_details(server) do
    %{
      hostname: server.db_hostname,
      port: server.db_port,
      username: server.db_username,
      password: server.db_password,
      database: server.db_name,
      ssl_mode: server.db_ssl_mode,
      ssl_cert: server.db_ssl_cert,
      ssl_key: server.db_ssl_key,
      ssl_ca_cert: server.db_ssl_ca_cert,
      socket_options: socket_options(server)
    }
  end

  defp decrypt(server) do
    %{
      server
      | db_password: decrypt_if_needed(server.db_password, "db_password"),
        ssh_private_key: decrypt_if_needed(server.ssh_private_key, "ssh_private_key")
    }
  end

  defp decrypt_if_needed(nil, _), do: nil

  defp decrypt_if_needed(encrypted, salt) do
    case Phoenix.Token.decrypt(QueryCanaryWeb.Endpoint, salt, encrypted, max_age: :infinity) do
      {:ok, decrypted} -> decrypted
      {:error, _} -> encrypted
    end
  end

  defp socket_options(server) do
    case :inet_res.gethostbyname(String.to_charlist(server.db_hostname), :inet6) do
      {:ok, {:hostent, _host, [], _, _, _}} -> [:inet6]
      _ -> []
    end
  end

  defp cleanup(state) do
    if ref = state.tunnel_ref do
      SSHTunnel.stop_tunnel(ref)
    end

    if conn = state.adapter_conn do
      safe_disconnect(state.adapter, conn)
    end
  end

  defp safe_disconnect(adapter, conn) do
    if function_exported?(adapter, :disconnect, 1) do
      try do
        adapter.disconnect(conn)
      catch
        _, _ -> :ok
      end
    else
      if is_pid(conn) and Process.alive?(conn), do: GenServer.stop(conn, :normal)
    end
  end

  defp adapter_for(%Server{db_engine: "postgresql"}),
    do: QueryCanary.Connections.Adapters.PostgreSQL

  defp adapter_for(%Server{db_engine: "mysql"}), do: QueryCanary.Connections.Adapters.MySQL

  defp adapter_for(%Server{db_engine: "clickhouse"}),
    do: QueryCanary.Connections.Adapters.ClickHouse

  defp adapter_for(%Server{db_engine: other}), do: raise("Unsupported database engine: #{other}")

  defp via(server_id),
    do: {:via, Registry, {QueryCanary.ConnectionRegistry, {:server, server_id}}}
end
