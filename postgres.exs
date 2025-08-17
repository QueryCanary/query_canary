Mix.install([
  {:postgrex, "~> 0.21.1"}
])

defmodule Main do
  require Logger

  def test do
    {:ok, pid} =
      Postgrex.start_link(
        database: "not_real",

        # Short timeouts
        connect_timeout: 5000,
        timeout: 5000,

        # Queue settings to fail fast
        queue_target: 50,
        queue_interval: 1000,
        max_restarts: 1,
        show_sensitive_data_on_connection_error: true,
        name: :"test_conn_#{System.unique_integer([:positive])}"
      )

    case Postgrex.query(pid, "SELECT 1;") do
      {:error, unhelpful_error} ->
        GenServer.stop(pid) |> dbg()

        {:ok, pid} =
          Postgrex.start_link(
            database: "query_canary_dev",

            # Short timeouts
            connect_timeout: 5000,
            timeout: 5000,

            # Queue settings to fail fast
            queue_target: 50,
            queue_interval: 1000,
            max_restarts: 1,
            show_sensitive_data_on_connection_error: true,
            name: :"test_conn_#{System.unique_integer([:positive])}"
          )

        Postgrex.query(pid, "SELECT 1") |> dbg()
    end
  end

  def test_simple do
    # Start the connection

    # Execute a literal query
    try do
      Process.flag(:trap_exit, true)

      {:ok, pid} =
        Postgrex.SimpleConnection.start_link(MyConnection, [],
          database: "query_canary_dev"
          # username: "foobar"
        )
        |> dbg()

      Postgrex.SimpleConnection.call(pid, {:query, "SELECT 1"}) |> dbg()

      # Postgrex.query(pid, "SELECT 1") |> dbg()
    rescue
      e ->
        dbg(e)
    end

    # => %Postgrex.Result{rows: [["1"]]}
  end
end

defmodule MyConnection do
  @behaviour Postgrex.SimpleConnection

  @impl true
  def init(_args) do
    {:ok, %{from: nil}}
  end

  @impl true
  def handle_call({:query, query}, from, state) do
    {:query, query, %{state | from: from}}
  end

  @impl true
  def handle_result(results, state) when is_list(results) do
    Postgrex.SimpleConnection.reply(state.from, results)

    {:noreply, state}
  end

  @impl true
  def handle_result(%Postgrex.Error{} = error, state) do
    Postgrex.SimpleConnection.reply(state.from, error)

    {:noreply, state}
  end

  @impl true
  def notify(_binary, _binary, _state) do
    :ok
  end
end

Main.test_simple()
