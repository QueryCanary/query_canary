defmodule QueryCanary.Connections.Adapters.SQLite do
  @moduledoc """
  SQLite adapter for database connections.

  Implements the database adapter behavior for SQLite databases.
  Primarily used for running unit tests.
  """

  require Logger

  @doc """
  Connects to an SQLite database.

  ## Parameters
    * conn_details - Connection details map

  ## Returns
    * {:ok, conn} - Connection successful
    * {:error, reason} - Connection failed
  """
  def connect(conn_details) do
    try do
      opts = [
        database: conn_details.database,
        timeout: 10_000
      ]

      case Exqlite.start_link(opts) do
        {:ok, pid} ->
          Process.put(:db_connection_pid, pid)
          {:ok, pid}

        {:error, reason} ->
          {:error, "Failed to connect: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "SQLite connection error: #{inspect(e)}"}
    end
  end

  @doc """
  Executes a query on an SQLite database.

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
      case Exqlite.query(conn, query, params) do
        {:ok, result} ->
          {:ok, format_results(result)}

        {:error, reason} ->
          {:error, "Query error: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "SQLite query error: #{inspect(e)}"}
    end
  end

  @doc """
  Lists tables in an SQLite database.

  ## Parameters
    * conn - Database connection

  ## Returns
    * {:ok, tables} - List of table names
    * {:error, reason} - Operation failed
  """
  def list_tables(conn) do
    query = """
    SELECT name FROM sqlite_master
    WHERE type = 'table'
    ORDER BY name;
    """

    case query(conn, query) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn %{name: table} -> table end)}

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
    PRAGMA table_info(#{table_name});
    """

    case query(conn, query) do
      {:ok, %{rows: rows}} ->
        schema =
          Enum.map(rows, fn %{
                              name: column_name,
                              type: data_type,
                              notnull: not_null,
                              dflt_value: default
                            } ->
            %{
              column_name: column_name,
              data_type: data_type,
              is_nullable: not_null == 0,
              column_default: default
            }
          end)

        {:ok, schema}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets complete database schema information.

  ## Parameters
    * conn - Database connection

  ## Returns
    * {:ok, schema} - Complete database schema information
    * {:error, reason} - Operation failed
  """
  def get_database_schema(conn) do
    case list_tables(conn) do
      {:ok, tables} ->
        schema =
          Enum.reduce(tables, %{}, fn table, acc ->
            case get_table_schema(conn, table) do
              {:ok, table_schema} ->
                Map.put(acc, table, table_schema)

              {:error, _reason} ->
                acc
            end
          end)

        {:ok, schema}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Formats query results into a more usable structure
  defp format_results(%Exqlite.Result{} = result) do
    columns = Enum.map(result.columns, &String.to_atom/1)

    rows =
      Enum.map(result.rows, fn row ->
        Enum.zip(columns, row) |> Map.new()
      end)

    %{
      rows: rows,
      columns: columns,
      num_rows: length(rows),
      raw: result
    }
  end
end
