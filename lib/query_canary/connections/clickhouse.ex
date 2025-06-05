defmodule QueryCanary.Connections.Adapters.ClickHouse do
  @moduledoc """
  ClickHouse adapter for database connections using the `ch` library.
  """

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
      database: conn_details.database
    ]

    dbg(opts)

    case Ch.start_link(opts) |> dbg() do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a query on a ClickHouse database.

  ## Parameters
    * conn - Connection options
    * query - SQL query string
    * params - Query parameters (not supported in HTTP API)

  ## Returns
    * {:ok, results} - Query successful
    * {:error, reason} - Query failed
  """
  def query(conn, query, params \\ []) do
    case Ch.query(conn, query, params) |> dbg() do
      {:ok, %Ch.Result{columns: columns, rows: rows}} ->
        row_maps = Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
        {:ok, %{rows: row_maps, columns: columns, num_rows: length(row_maps), raw: rows}}

      {:error, reason} ->
        {:error, reason}
    end
  end

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
    case query(conn, "DESCRIBE TABLE {$0:String}", [table_name]) do
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
end
