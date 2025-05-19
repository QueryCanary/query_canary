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
        timeout: 10_000,
        socket_options: conn_details.socket_options
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
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
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

  @doc """
  Gets complete database schema information in a single query.

  ## Parameters
    * conn - Database connection
    * database_name - The database name

  ## Returns
    * {:ok, schema} - Complete database schema information
    * {:error, reason} - Operation failed
  """
  def get_database_schema(conn, database_name) do
    # Query to get all tables and their columns in one go
    query = """
    SELECT
       table_name,
       column_name,
       data_type
    FROM information_schema.columns
    WHERE table_catalog = $1 and table_schema = 'public'
    ORDER BY ordinal_position;
    """

    case query(conn, query, [database_name]) do
      {:ok, %{rows: rows}} ->
        # Process the rows into a structured schema map

        schema =
          Enum.reduce(rows, %{}, fn %{
                                      table_name: table_name,
                                      column_name: column_name,
                                      data_type: data_type
                                    },
                                    acc ->
            entry = %{
              detail: data_type,
              label: column_name,
              section: table_name,
              type: "keyword"
            }

            Map.update(acc, table_name, [entry], fn existing -> [entry | existing] end)
          end)
          |> Map.new(fn {table, fields} -> {table, Enum.reverse(fields)} end)

        {:ok, schema}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Formats query results into a more usable structure
  defp format_results(%Postgrex.Result{} = result) do
    # Create indexed column names to handle duplicates
    {columns, _} =
      Enum.reduce(result.columns, {[], %{}}, fn col_name, {cols, counts} ->
        # Get the current count for this column name (default 0)
        count = Map.get(counts, col_name, 0)

        # Create a unique column name if needed
        col_atom =
          if count > 0 do
            # Add a suffix for duplicate columns
            String.to_atom("#{col_name}_#{count}")
          else
            String.to_atom(col_name)
          end

        # Update counts and add to columns list
        {cols ++ [col_atom], Map.put(counts, col_name, count + 1)}
      end)

    # Map rows using the deduplicated column names
    rows =
      Enum.map(result.rows, fn row ->
        Enum.zip(columns, row) |> Map.new()
      end)

    # Store original column names alongside deduplicated ones
    %{
      rows: rows,
      columns: columns,
      original_columns: result.columns,
      num_rows: result.num_rows,
      raw: result
    }
  end
end
