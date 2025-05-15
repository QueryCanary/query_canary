defmodule QueryCanary.Connections.Adapters.MySQL do
  @moduledoc """
  MySQL adapter for database connections.

  Implements the database adapter behavior for MySQL databases.
  """

  require Logger

  @doc """
  Connects to a MySQL database.

  ## Parameters
    * conn_details - Connection details map

  ## Returns
    * {:ok, conn} - Connection successful
    * {:error, reason} - Connection failed
  """
  def connect(conn_details) do
    try do
      opts = [
        hostname: conn_details.hostname,
        port: conn_details.port,
        username: conn_details.username,
        password: conn_details.password,
        database: conn_details.database,
        timeout: 10_000
      ]

      case MyXQL.start_link(opts) do
        {:ok, pid} ->
          Process.put(:db_connection_pid, pid)
          {:ok, pid}

        {:error, reason} ->
          {:error, "Failed to connect: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "MySQL connection error: #{inspect(e)}"}
    end
  end

  @doc """
  Executes a query on a MySQL database.

  ## Parameters
    * conn - Database connection
    * query - SQL query string
    * params - Query parameters

  ## Returns
    * {:ok, results} - Query successful
    * {:error, reason} - Query failed
  """
  def query(conn, query, params \\ []) do
    try do
      case MyXQL.query(conn, query, params) do
        {:ok, result} ->
          {:ok, format_results(result)}

        {:error, %MyXQL.Error{} = error} ->
          {:error, error.message || inspect(error)}

        {:error, reason} ->
          {:error, "Query error: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "MySQL query error: #{inspect(e)}"}
    end
  end

  @doc """
  Lists tables in a MySQL database.

  ## Parameters
    * conn - Database connection

  ## Returns
    * {:ok, tables} - List of table names
    * {:error, reason} - Operation failed
  """
  def list_tables(conn) do
    query = "SHOW TABLES;"

    case query(conn, query) do
      {:ok, %{rows: rows}} ->
        tables = Enum.map(rows, fn row -> Map.values(row) |> List.first() end)
        {:ok, tables}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets schema information for a specific table.

  ## Parameters
    * conn - Database connection
    * table_name - Name of the table

  ## Returns
    * {:ok, schema} - Table schema information
    * {:error, reason} - Operation failed
  """
  def get_table_schema(conn, table_name) do
    query = "DESCRIBE `#{table_name}`;"

    case query(conn, query) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  # Formats query results into a more usable structure
  defp format_results(%MyXQL.Result{} = result) do
    columns = Enum.map(result.columns || [], &String.to_atom/1)

    rows =
      if result.rows do
        Enum.map(result.rows, fn row ->
          Enum.zip(columns, row) |> Map.new()
        end)
      else
        []
      end

    %{
      rows: rows,
      columns: columns,
      num_rows: result.num_rows,
      last_insert_id: result.last_insert_id,
      raw: result
    }
  end
end
