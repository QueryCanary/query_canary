defmodule QueryCanary.Connections.Adapters.PostgreSQL do
  @moduledoc """
  PostgreSQL adapter for database connections.

  Implements the database adapter behavior for PostgreSQL databases.
  """

  require Logger

  @doc """
  Connects to a PostgreSQL database.

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

      case Postgrex.start_link(opts) do
        {:ok, pid} ->
          Process.put(:db_connection_pid, pid)
          {:ok, pid}

        {:error, reason} ->
          {:error, "Failed to connect: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "PostgreSQL connection error: #{inspect(e)}"}
    end
  end

  @doc """
  Executes a query on a PostgreSQL database.

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
      case Postgrex.query(conn, query, params) do
        {:ok, result} ->
          {:ok, format_results(result)}

        {:error, %Postgrex.Error{} = error} ->
          {:error, error.postgres.message || inspect(error)}

        {:error, reason} ->
          {:error, "Query error: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "PostgreSQL query error: #{inspect(e)}"}
    end
  end

  @doc """
  Lists tables in a PostgreSQL database.

  ## Parameters
    * conn - Database connection

  ## Returns
    * {:ok, tables} - List of table names
    * {:error, reason} - Operation failed
  """
  def list_tables(conn) do
    query = """
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public'
    ORDER BY table_name;
    """

    case query(conn, query) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn %{table_name: table} ->
           table
         end)}

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
    query = """
    SELECT
      column_name,
      data_type,
      is_nullable,
      column_default
    FROM information_schema.columns
    WHERE table_name = $1
    ORDER BY ordinal_position;
    """

    case query(conn, query, [table_name]) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  # Formats query results into a more usable structure
  defp format_results(%Postgrex.Result{} = result) do
    columns = Enum.map(result.columns, &String.to_atom/1)

    rows =
      Enum.map(result.rows, fn row ->
        Enum.zip(columns, row) |> Map.new()
      end)

    %{
      rows: rows,
      columns: columns,
      num_rows: result.num_rows,
      raw: result
    }
  end
end
