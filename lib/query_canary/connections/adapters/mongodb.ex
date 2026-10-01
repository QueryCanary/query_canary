defmodule QueryCanary.Connections.Adapters.MongoDB do
  @moduledoc """
  MongoDB queries expressed as JSON find, count, distinct or aggregate commands.
  Cursors are fully consumed and BSON values are converted for result storage.
  """
  @behaviour QueryCanary.Connections.Adapter

  @query_options %{
    "projection" => :projection,
    "sort" => :sort,
    "limit" => :limit,
    "skip" => :skip,
    "batchSize" => :batch_size,
    "maxTimeMS" => :max_time,
    "allowDiskUse" => :allow_disk_use,
    "collation" => :collation,
    "hint" => :hint,
    "comment" => :comment
  }

  def connect(details) do
    opts = [
      hostname: details.hostname,
      port: details.port || 27017,
      database: details.database,
      username: details.username,
      password: details.password,
      auth_source: details[:auth_source] || details.database,
      direct_connection: details[:direct_connection] || false,
      socket_options: details[:socket_options] || [],
      pool_size: 1,
      connect_timeout: 3_000,
      timeout: 3_000
    ]

    safely(fn ->
      with {:ok, pid} <- Mongo.start_link(opts ++ ssl_options(details)) do
        case safely(fn ->
               Mongo.command(pid, [ping: 1], timeout: 3_000, checkout_timeout: 3_000)
             end) do
          {:ok, _} ->
            {:ok, pid}

          {:error, reason} ->
            disconnect(pid)
            {:error, reason}
        end
      end
    end)
  end

  def query(conn, query, params \\ [], opts \\ []) do
    safely(fn ->
      with {:ok, command} <- parse_query(query, params) do
        execute(conn, command, query_timeout_options(opts))
      end
    end)
  end

  @doc "Parses JSON and substitutes whole-string positional parameters and Extended JSON values."
  def parse_query(query, params \\ []) do
    safely(fn ->
      case Jason.decode(query) do
        {:ok, command} when is_map(command) -> {:ok, decode_values(command, params)}
        {:ok, _} -> {:error, "MongoDB queries must be a JSON object"}
        {:error, _} -> {:error, "Invalid MongoDB JSON query"}
      end
    end)
  end

  defp execute(conn, %{"find" => collection} = command, opts) when is_binary(collection) do
    conn
    |> Mongo.find(collection, command["filter"] || %{}, query_options(command, opts))
    |> format_cursor()
  end

  defp execute(conn, %{"aggregate" => collection, "pipeline" => pipeline} = command, opts)
       when is_binary(collection) and is_list(pipeline) do
    conn
    |> Mongo.aggregate(collection, pipeline, query_options(command, opts))
    |> format_cursor()
  end

  defp execute(conn, %{"count" => collection} = command, opts) when is_binary(collection) do
    case Mongo.count_documents(
           conn,
           collection,
           command["query"] || %{},
           query_options(command, opts)
         ) do
      {:ok, count} -> {:ok, format_results([%{"value" => count}])}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(conn, %{"distinct" => collection, "key" => key} = command, opts)
       when is_binary(collection) and is_binary(key) do
    case Mongo.distinct(
           conn,
           collection,
           key,
           command["query"] || %{},
           query_options(command, opts)
         ) do
      {:ok, values} -> {:ok, format_results(Enum.map(values, &%{"value" => &1}))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(conn, %{"ping" => 1}, opts), do: run_command(conn, [ping: 1], opts)
  defp execute(conn, %{"buildInfo" => 1}, opts), do: run_command(conn, [buildInfo: 1], opts)

  defp execute(_, _, _),
    do: {:error, "Use a MongoDB find, count, distinct or aggregate JSON command"}

  defp run_command(conn, command, opts) do
    case Mongo.command(conn, command, opts) do
      {:ok, result} ->
        {:ok, format_results([Map.drop(result, ["ok", "$clusterTime", "operationTime"])])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_tables(conn) do
    safely(fn ->
      {:ok, conn |> Mongo.show_collections(query_timeout_options([])) |> Enum.sort()}
    end)
  end

  def get_table_schema(conn, collection) do
    safely(fn ->
      case Mongo.find(conn, collection, %{}, [limit: 100] ++ query_timeout_options([])) do
        {:error, reason} ->
          {:error, reason}

        cursor ->
          fields =
            cursor
            |> Enum.flat_map(fn document ->
              Enum.map(document, fn {key, value} -> {key, bson_type(value)} end)
            end)
            |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
            |> Enum.sort()
            |> Enum.map(fn {field, types} ->
              %{
                label: field,
                detail: types |> Enum.uniq() |> Enum.sort() |> Enum.join(" | "),
                section: collection,
                type: "keyword"
              }
            end)

          {:ok, fields}
      end
    end)
  end

  def get_database_schema(conn, _database) do
    with {:ok, collections} <- list_tables(conn) do
      Enum.reduce_while(collections, {:ok, %{}}, fn collection, {:ok, schema} ->
        case get_table_schema(conn, collection) do
          {:ok, fields} -> {:cont, {:ok, Map.put(schema, collection, fields)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  def disconnect(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp query_options(command, opts) do
    options =
      Enum.flat_map(@query_options, fn {key, option} ->
        if Map.has_key?(command, key), do: [{option, command[key]}], else: []
      end)

    options =
      case command["cursor"] do
        %{"batchSize" => size} -> Keyword.put(options, :batch_size, size)
        _ -> options
      end

    Keyword.merge(options, opts)
  end

  defp query_timeout_options(opts) do
    opts = Keyword.put_new(opts, :timeout, 4_000)
    Keyword.put_new(opts, :checkout_timeout, opts[:timeout])
  end

  defp format_cursor({:error, reason}), do: {:error, reason}
  defp format_cursor(cursor), do: {:ok, cursor |> Enum.to_list() |> format_results()}

  @doc "Converts query documents to the shared result shape with JSON-safe BSON values."
  def format_results(documents) do
    rows = Enum.map(documents, &normalize_value/1)
    columns = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()
    # Scalar metrics prefer an explicitly projected value over an aggregation group id.
    columns = if "value" in columns, do: ["value" | List.delete(columns, "value")], else: columns
    %{rows: rows, columns: columns, original_columns: columns, num_rows: length(rows), raw: rows}
  end

  defp decode_values(%{"$oid" => value} = doc, _) when map_size(doc) == 1,
    do: BSON.ObjectId.decode!(value)

  defp decode_values(%{"$date" => value} = doc, _) when map_size(doc) == 1 do
    case value do
      value when is_integer(value) ->
        DateTime.from_unix!(value, :millisecond)

      value when is_binary(value) ->
        {:ok, datetime, _} = DateTime.from_iso8601(value)
        datetime
    end
  end

  defp decode_values(%{"$numberDecimal" => value} = doc, _) when map_size(doc) == 1,
    do: Decimal.new(value)

  defp decode_values(%{"$numberLong" => value} = doc, _) when map_size(doc) == 1,
    do: String.to_integer(value)

  defp decode_values(doc, params) when is_map(doc),
    do: Map.new(doc, fn {key, value} -> {key, decode_values(value, params)} end)

  defp decode_values(values, params) when is_list(values),
    do: Enum.map(values, &decode_values(&1, params))

  defp decode_values(value, params) when is_binary(value) do
    case Regex.run(~r/^\$([1-9]\d*)$/, value) do
      [_, index] ->
        case Enum.fetch(params, String.to_integer(index) - 1) do
          {:ok, parameter} -> parameter
          :error -> raise ArgumentError, "Missing MongoDB query parameter #{value}"
        end

      _ ->
        value
    end
  end

  defp decode_values(value, _params), do: value

  defp normalize_value(%BSON.ObjectId{} = value), do: to_string(value)
  defp normalize_value(%BSON.Binary{binary: value}), do: Base.encode64(value)
  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp normalize_value(%BSON.LongNumber{value: value}), do: value
  defp normalize_value(%_{} = value), do: value |> Map.from_struct() |> normalize_value()

  defp normalize_value(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, normalize_value(value)} end)

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp bson_type(%BSON.ObjectId{}), do: "objectId"
  defp bson_type(%DateTime{}), do: "date"
  defp bson_type(%Decimal{}), do: "decimal"
  defp bson_type(nil), do: "null"
  defp bson_type(value) when is_boolean(value), do: "boolean"
  defp bson_type(value) when is_integer(value), do: "integer"
  defp bson_type(value) when is_float(value), do: "double"
  defp bson_type(value) when is_binary(value), do: "string"
  defp bson_type(value) when is_list(value), do: "array"
  defp bson_type(_), do: "object"

  defp ssl_options(%{ssl_mode: mode} = details)
       when mode in ["require", "verify-ca", "verify-full"] do
    ssl_opts =
      if mode == "require" do
        [verify: :verify_none]
      else
        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: to_charlist(details[:tls_hostname] || details.hostname)
        ]
      end

    ssl_opts =
      if mode == "verify-full" do
        Keyword.put(ssl_opts, :customize_hostname_check,
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        )
      else
        ssl_opts
      end

    ssl_opts =
      case details[:ssl_ca_cert] do
        "-----BEGIN" <> _ = pem ->
          certs = for {:Certificate, der, :not_encrypted} <- :public_key.pem_decode(pem), do: der
          Keyword.put(ssl_opts, :cacerts, certs)

        path when is_binary(path) and path != "" ->
          ssl_opts |> Keyword.delete(:cacerts) |> Keyword.put(:cacertfile, to_charlist(path))

        _ ->
          ssl_opts
      end

    [ssl: true, ssl_opts: ssl_opts]
  end

  defp ssl_options(_), do: [ssl: false]

  defp safely(fun) do
    case fun.() do
      {:error, reason} -> {:error, error_message(reason)}
      result -> result
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, "MongoDB connection error: #{inspect(reason)}"}
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(%{__exception__: true} = reason), do: Exception.message(reason)
  defp error_message(reason), do: inspect(reason)
end
