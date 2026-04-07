defmodule QueryCanary.Connections.Adapters.ClickHouse do
  @moduledoc """
  ClickHouse adapter for database connections using the `ch` library.
  """

  @behaviour QueryCanary.Connections.Adapter

  alias Decimal, as: DecimalValue

  @doc """
  Connects to a ClickHouse database using the `ch` library.

  ## Parameters
    * conn_details - Connection details map

  ## Returns
    * {:ok, conn} - Connection successful
    * {:error, reason} - Connection failed
  """
  def connect(conn_details) do
    opts = [
      scheme: "http",
      hostname: conn_details.hostname,
      port: conn_details.port || 8123,
      username: conn_details.username,
      password: conn_details.password,
      database: conn_details.database,
      pool_size: 1,
      timeout: 5000,
      connect_timeout: 5000
    ]

    case Ch.start_link(opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a query on a ClickHouse database.

  ## Parameters
    * conn - Connection options
    * query - SQL query string
    * params - Query parameters

  ## Returns
    * {:ok, results} - Query successful
    * {:error, reason} - Query failed
  """
  def query(conn, query, params \\ []) do
    {query, params} = normalize_query(query, params)

    case Ch.query(conn, query, params) do
      {:ok, %Ch.Result{columns: columns, rows: rows}} ->
        row_maps = Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
        {:ok, %{rows: row_maps, columns: columns, num_rows: length(row_maps), raw: rows}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_query(query, params) when is_binary(query) and is_list(params) do
    if Regex.match?(~r/(?<!\{)\$[1-9]\d*/, query) do
      {rewrite_postgres_placeholders(query, params), params}
    else
      {query, params}
    end
  end

  defp normalize_query(query, params), do: {query, params}

  defp rewrite_postgres_placeholders(query, params) do
    Regex.replace(~r/(?<!\{)\$([1-9]\d*)/, query, fn _match, raw_index ->
      index = String.to_integer(raw_index) - 1

      case Enum.fetch(params, index) do
        {:ok, value} -> "{$#{index}:#{clickhouse_param_type(value)}}"
        :error -> "$#{raw_index}"
      end
    end)
  end

  defp clickhouse_param_type(%DateTime{}), do: "DateTime64(6, 'UTC')"
  defp clickhouse_param_type(%NaiveDateTime{}), do: "DateTime64(6)"
  defp clickhouse_param_type(%Date{}), do: "Date"
  defp clickhouse_param_type(%Time{}), do: "String"
  defp clickhouse_param_type(%DecimalValue{}), do: "Decimal(38, 10)"
  defp clickhouse_param_type(value) when is_integer(value), do: "Int64"
  defp clickhouse_param_type(value) when is_float(value), do: "Float64"
  defp clickhouse_param_type(value) when is_boolean(value), do: "Bool"
  defp clickhouse_param_type(value) when is_binary(value), do: "String"
  defp clickhouse_param_type(_value), do: "String"

  @doc """
  Lists tables in a ClickHouse database.
  """
  def list_tables(conn) do
    case query(conn, "SHOW TABLES") do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn row -> Map.values(row) |> List.first() end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets schema information for a specific table.
  """
  def get_table_schema(conn, table_name) do
    case query(conn, "DESCRIBE TABLE #{table_name}") do
      {:ok, %{rows: rows}} -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets complete database schema information in a single query.
  """
  def get_database_schema(conn, database_name) do
    sql =
      "SELECT table, name, type FROM system.columns WHERE database = {$0:String} ORDER BY table, position"

    case query(conn, sql, [database_name]) do
      {:ok, %{rows: rows}} ->
        schema =
          Enum.reduce(rows, %{}, fn %{"table" => table, "name" => column, "type" => type}, acc ->
            entry = %{
              detail: type,
              label: column,
              section: table,
              type: "keyword"
            }

            Map.update(acc, table, [entry], fn existing -> [entry | existing] end)
          end)
          |> Map.new(fn {table, fields} -> {table, Enum.reverse(fields)} end)

        {:ok, schema}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Disconnects from a ClickHouse database.

  ## Parameters
    * pid - The process ID of the connection

  ## Returns
    * :ok - Disconnection successful
  """
  def disconnect(pid) when is_pid(pid) do
    try do
      GenServer.stop(pid, :normal)
      :ok
    catch
      _, _ -> :ok
    end
  end
end
