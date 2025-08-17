defmodule QueryCanary.Connections.Adapters.PostgreSQL do
  @moduledoc """
  PostgreSQL adapter for database connections.

  Implements the database adapter behavior for PostgreSQL databases.
  """

  require Logger

  @behaviour QueryCanary.Connections.Adapter

  @doc """
  Connects to a PostgreSQL database.

  ## Parameters
    * conn_details - Connection details map

  ## Returns
    * {:ok, conn} - Connection successful
    * {:error, reason} - Connection failed
  """
  def connect(conn_details) do
    Logger.metadata(db_hostname: conn_details.hostname)
    Logger.info("QueryCanary.Connections: Connecting to #{conn_details.hostname}")

    base_opts = [
      hostname: conn_details.hostname,
      port: conn_details.port,
      username: conn_details.username,
      password: conn_details.password,
      database: conn_details.database,
      socket_options: Map.get(conn_details, :socket_options, [])
      # we assign a name only after success (avoid clashes across attempts)
      # name: will be injected on success
    ]

    ssl_mode = Map.get(conn_details, :ssl_mode, "allow")

    case connect_with_sslmode(base_opts, ssl_mode, conn_details) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  # SSL mode handling -------------------------------------------------------
  defp connect_with_sslmode(base_opts, ssl_mode, conn_details) do
    attempts = attempts_for_mode(ssl_mode)

    Enum.reduce_while(attempts, {:error, :no_attempt_succeeded}, fn attempt, _acc ->
      case do_attempt(base_opts, attempt, ssl_mode, conn_details) do
        {:ok, _pid} = ok ->
          {:halt, ok}

        {:error, reason} ->
          if fallback_allowed?(ssl_mode, attempt, reason) do
            {:cont, {:error, reason}}
          else
            {:halt, {:error, reason}}
          end
      end
    end)
  end

  # Ordered attempts per libpq semantics
  # disable      -> [:plain]
  # allow        -> [:plain, :ssl] (only use SSL if server forces it / plain fails)
  # prefer       -> [:ssl, :plain]
  # require      -> [:ssl]
  # verify-ca    -> [:ssl]
  # verify-full  -> [:ssl]
  defp attempts_for_mode("disable"), do: [:plain]
  defp attempts_for_mode("allow"), do: [:plain, :ssl]
  defp attempts_for_mode("prefer"), do: [:ssl, :plain]
  defp attempts_for_mode("require"), do: [:ssl]
  defp attempts_for_mode("verify-ca"), do: [:ssl]
  defp attempts_for_mode("verify-full"), do: [:ssl]
  defp attempts_for_mode(_), do: [:ssl]

  # Decide if we should fallback after a failure for the given attempt
  defp fallback_allowed?("allow", :plain, _reason), do: true
  defp fallback_allowed?("prefer", :ssl, _reason), do: true
  defp fallback_allowed?(_, _, _), do: false

  defp do_attempt(base_opts, :plain, _ssl_mode, _details) do
    opts = add_name(base_opts)
    Postgrex.start_link(opts)
  end

  defp do_attempt(base_opts, :ssl, ssl_mode, conn_details) do
    case build_ssl_opts(ssl_mode, conn_details) do
      {:ok, ssl_opts} ->
        opts = base_opts |> Keyword.put(:ssl, ssl_opts) |> add_name()
        Postgrex.start_link(opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_name(opts) do
    Keyword.put_new(opts, :name, :"db_conn_#{System.unique_integer([:positive])}")
  end

  # Build :ssl option keyword list for :ssl -> :ssl.connect
  defp build_ssl_opts(mode, _details) when mode in ["require", "allow", "prefer"] do
    # No certificate validation
    {:ok, [verify: :verify_none]}
  end

  defp build_ssl_opts("verify-ca", details) do
    with {:ok, ca_opts} <- ca_opts(details) do
      {:ok,
       [
         verify: :verify_peer,
         server_name_indication: to_charlist(details.hostname)
       ] ++ ca_opts}
    end
  end

  defp build_ssl_opts("verify-full", details) do
    with {:ok, ca_opts} <- ca_opts(details) do
      hostname = to_charlist(details.hostname)

      hostname_check = [
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]

      {:ok,
       [
         verify: :verify_peer,
         server_name_indication: hostname
       ] ++ hostname_check ++ ca_opts}
    end
  end

  defp build_ssl_opts("disable", _), do: {:error, :ssl_disabled}
  defp build_ssl_opts(_other, details), do: build_ssl_opts("require", details)

  defp ca_opts(details) do
    cond do
      details[:ssl_ca_cert] && String.starts_with?(details[:ssl_ca_cert], "-----BEGIN") ->
        # PEM string
        {:ok, [cacerts: [details[:ssl_ca_cert]]]}

      details[:ssl_ca_cert] ->
        # file path
        {:ok, [cacertfile: details[:ssl_ca_cert]]}

      true ->
        # Rely on Erlang's default CA store (may be empty) – user should supply one
        {:ok, []}
    end
  end

  # ------------------------------------------------------------------------
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

  @doc """
  Disconnects from a PostgreSQL database.

  ## Parameters
    * pid - Process ID of the connection

  ## Returns
    * :ok - Disconnection successful
    * :error - Disconnection failed
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
