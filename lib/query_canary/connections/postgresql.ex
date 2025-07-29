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
        socket_options: Map.get(conn_details, :socket_options, [])
      ]

      # Build advanced SSL options if present
      ssl_mode = Map.get(conn_details, :ssl_mode, "allow")

      ssl_opts =
        [
          # Map ssl_mode to verify options
          verify:
            case ssl_mode do
              "verify-full" -> :verify_peer
              "verify-ca" -> :verify_peer
              "require" -> :verify_none
              "prefer" -> :verify_none
              "allow" -> :verify_none
              _ -> :verify_none
            end
        ]
        |> maybe_add_ssl_cert(conn_details)
        |> maybe_add_ssl_key(conn_details)
        |> maybe_add_ssl_ca_cert(conn_details)
        |> Enum.reject(&is_nil/1)

      opts = opts ++ [ssl: true, ssl_opts: ssl_opts]

      with {:ok, pid} <- Postgrex.start_link(opts),
           {:ok, _res} <- query(pid, "SELECT 1;") do
        {:ok, pid}
      else
        {:error, _message} when ssl_mode in ["allow", "prefer"] ->
          # Retry without SSL
          opts_no_ssl = Keyword.delete(opts, :ssl)
          opts_no_ssl = Keyword.delete(opts_no_ssl, :ssl_opts)
          Postgrex.start_link(opts_no_ssl)

        error ->
          {:error, "Failed to connect: #{inspect(error)}"}
      end
    rescue
      e -> {:error, "PostgreSQL connection error: #{inspect(e)}"}
    end
  end

  defp maybe_add_ssl_cert(opts, conn_details) do
    if cert = Map.get(conn_details, :ssl_cert) do
      # Accept PEM string or file path
      if String.starts_with?(cert, "-----BEGIN CERTIFICATE") do
        Keyword.put(opts, :cert, cert)
      else
        Keyword.put(opts, :certfile, cert)
      end
    else
      opts
    end
  end

  defp maybe_add_ssl_key(opts, conn_details) do
    if key = Map.get(conn_details, :ssl_key) do
      if String.starts_with?(key, "-----BEGIN") do
        Keyword.put(opts, :key, key)
      else
        Keyword.put(opts, :keyfile, key)
      end
    else
      opts
    end
  end

  defp maybe_add_ssl_ca_cert(opts, conn_details) do
    if ca = Map.get(conn_details, :ssl_ca_cert) do
      if String.starts_with?(ca, "-----BEGIN CERTIFICATE") do
        Keyword.put(opts, :cacerts, [ca])
      else
        Keyword.put(opts, :cacertfile, ca)
      end
    else
      opts
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
