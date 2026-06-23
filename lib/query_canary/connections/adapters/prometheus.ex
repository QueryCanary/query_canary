defmodule QueryCanary.Connections.Adapters.Prometheus do
  @moduledoc """
  Prometheus adapter for HTTP API based query execution.
  """

  @behaviour QueryCanary.Connections.Adapter

  @build_info_query "__query_canary_prometheus_build_info__"
  @default_timeout 5_000

  @doc """
  Connects to a Prometheus server and validates the endpoint is reachable.
  """
  def connect(conn_details) do
    client = build_client(conn_details)

    case fetch_build_info(client) do
      {:ok, _} ->
        {:ok, client}

      {:error, build_info_error} ->
        case healthy?(client) do
          :ok -> {:ok, client}
          {:error, _reason} -> {:error, build_info_error}
        end
    end
  end

  @doc """
  Executes an instant PromQL query against Prometheus.
  """
  def query(conn, query), do: query(conn, query, [], [])
  def query(conn, query, params), do: query(conn, query, params, [])

  def query(_conn, _query, params, _opts) when params != [] do
    {:error, "Prometheus queries do not support positional parameters"}
  end

  def query(conn, @build_info_query, [], opts) do
    case fetch_build_info(conn, opts) do
      {:ok, build_info} ->
        row =
          build_info
          |> Map.take(["version", "revision", "branch", "buildUser", "buildDate", "goVersion"])
          |> Map.reject(fn {_key, value} -> is_nil(value) end)

        columns = Map.keys(row) |> Enum.sort()

        {:ok,
         %{
           rows: [row],
           columns: columns,
           original_columns: columns,
           num_rows: 1,
           raw: build_info
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def query(conn, promql, [], opts) do
    with {:ok, %{"resultType" => result_type, "result" => result} = raw} <-
           api_get(conn, "/api/v1/query", [params: [query: promql]], opts) do
      rows = format_query_rows(result_type, result)
      columns = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()

      {:ok,
       %{
         rows: rows,
         columns: columns,
         original_columns: columns,
         num_rows: length(rows),
         raw: raw
       }}
    end
  end

  @doc """
  Lists metric names exposed by Prometheus.
  """
  def list_tables(conn) do
    case api_get(conn, "/api/v1/label/__name__/values") do
      {:ok, metrics} when is_list(metrics) ->
        {:ok, Enum.sort(metrics)}

      {:ok, other} ->
        {:error, "Unexpected metric listing response: #{inspect(other)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds a schema-like list of label names for a single metric.
  """
  def get_table_schema(conn, table_name) do
    with {:ok, series} <- fetch_series(conn, table_name) do
      {:ok, format_table_schema(table_name, series)}
    end
  end

  @doc """
  Builds a schema map for all metrics returned by Prometheus.
  """
  def get_database_schema(conn, _database_name) do
    with {:ok, metrics} <- list_tables(conn) do
      Enum.reduce_while(metrics, {:ok, %{}}, fn metric, {:ok, acc} ->
        case get_table_schema(conn, metric) do
          {:ok, fields} ->
            {:cont, {:ok, Map.put(acc, metric, fields)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  def disconnect(_conn), do: :ok

  def version_query, do: @build_info_query

  defp build_client(conn_details) do
    scheme = infer_scheme(conn_details)

    base_options =
      [
        base_url: "#{scheme}://#{conn_details.hostname}:#{conn_details.port}",
        receive_timeout: @default_timeout,
        connect_options: [timeout: @default_timeout],
        retry: false
      ]
      |> maybe_enable_inet6(conn_details)
      |> maybe_add_auth(conn_details)

    Req.new(Keyword.merge(base_options, Map.get(conn_details, :req_options, [])))
  end

  defp maybe_enable_inet6(options, %{socket_options: socket_options})
       when is_list(socket_options) do
    if :inet6 in socket_options do
      Keyword.put(options, :inet6, true)
    else
      options
    end
  end

  defp maybe_enable_inet6(options, _conn_details), do: options

  defp maybe_add_auth(options, conn_details) do
    username = Map.get(conn_details, :username)
    password = Map.get(conn_details, :password)

    if present?(username) or present?(password) do
      Keyword.put(options, :auth, {:basic, "#{username}:#{password}"})
    else
      options
    end
  end

  defp infer_scheme(conn_details) do
    ssl_mode = Map.get(conn_details, :ssl_mode, "disable")

    cond do
      ssl_mode in ["require", "verify-ca", "verify-full"] -> "https"
      Map.get(conn_details, :port) == 443 -> "https"
      true -> "http"
    end
  end

  defp healthy?(conn) do
    case Req.get(conn, url: "/-/healthy") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, http_error(status, body)}
      {:error, reason} -> {:error, format_transport_error(reason)}
    end
  end

  defp fetch_build_info(conn, opts \\ []) do
    api_get(conn, "/api/v1/status/buildinfo", [], opts)
  end

  defp fetch_series(conn, metric_name) do
    case api_get(conn, "/api/v1/series", params: [{"match[]", metric_name}]) do
      {:ok, series} when is_list(series) ->
        {:ok, series}

      {:ok, other} ->
        {:error, "Unexpected series response for #{metric_name}: #{inspect(other)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_get(conn, path, request_options \\ [], query_opts \\ []) do
    request_options =
      [url: path]
      |> Keyword.merge(request_options)
      |> Keyword.merge(req_timeout_options(conn, query_opts))

    case Req.get(conn, request_options) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, data}

      {:ok, %{status: 200, body: %{"status" => "error", "error" => error}}} ->
        {:error, error}

      {:ok, %{status: 200, body: body}} ->
        {:error, "Unexpected Prometheus response: #{inspect(body)}"}

      {:ok, %{status: status, body: body}} ->
        {:error, http_error(status, body)}

      {:error, reason} ->
        {:error, format_transport_error(reason)}
    end
  end

  defp http_error(status, %{"error" => error}), do: "HTTP #{status}: #{error}"
  defp http_error(status, body) when is_binary(body), do: "HTTP #{status}: #{body}"
  defp http_error(status, body), do: "HTTP #{status}: #{inspect(body)}"

  defp format_transport_error(%{reason: reason}), do: "Transport error: #{inspect(reason)}"
  defp format_transport_error(%_{} = error), do: Exception.message(error)
  defp format_transport_error(reason), do: "Transport error: #{inspect(reason)}"

  defp req_timeout_options(conn, opts) do
    case Keyword.get(opts, :timeout) do
      nil ->
        []

      timeout ->
        connect_options =
          conn
          |> Req.Request.get_option(:connect_options, [])
          |> Keyword.put(:timeout, timeout)

        [receive_timeout: timeout, connect_options: connect_options]
    end
  end

  defp format_query_rows("vector", result), do: Enum.map(result, &format_vector_row/1)

  defp format_query_rows("matrix", result) do
    Enum.map(result, fn %{"metric" => metric, "values" => values} ->
      metric
      |> Map.delete("__name__")
      |> Map.put("values", Enum.map(values, &format_sample/1))
    end)
  end

  defp format_query_rows("scalar", [_timestamp, value]),
    do: [%{"value" => normalize_value(value)}]

  defp format_query_rows("string", [_timestamp, value]), do: [%{"value" => value}]

  defp format_query_rows(_other, result) when is_list(result), do: result
  defp format_query_rows(_other, result), do: [result]

  defp format_vector_row(%{"metric" => metric, "value" => [_timestamp, value]}) do
    metric
    |> Map.delete("__name__")
    |> Map.put("value", normalize_value(value))
  end

  defp format_sample([timestamp, value]) do
    %{"timestamp" => normalize_timestamp(timestamp), "value" => normalize_value(value)}
  end

  defp format_table_schema(metric_name, series) do
    label_entries =
      series
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.reject(&(&1 == "__name__"))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn label_name ->
        %{
          detail: "label",
          label: label_name,
          section: metric_name,
          type: "keyword"
        }
      end)

    label_entries ++
      [
        %{detail: "unix timestamp", label: "timestamp", section: metric_name, type: "keyword"},
        %{detail: "sample value", label: "value", section: metric_name, type: "keyword"}
      ]
  end

  defp normalize_timestamp(timestamp) when is_number(timestamp), do: timestamp

  defp normalize_timestamp(timestamp) when is_binary(timestamp) do
    case Float.parse(timestamp) do
      {value, _} -> value
      :error -> timestamp
    end
  end

  defp normalize_value(value) when is_number(value), do: value

  defp normalize_value(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> value
    end
  end

  defp present?(value), do: not is_nil(value) and value != ""
end
