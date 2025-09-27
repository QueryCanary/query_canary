defmodule QueryCanary.Metrics do
  @moduledoc """
  Context for SQL-powered metrics: definitions, execution, and persistence.
  """
  import Ecto.Query, warn: false
  alias QueryCanary.Repo
  alias QueryCanary.Metrics.{Metric, MetricResult}
  alias QueryCanary.Repo
  alias QueryCanary.Servers.Server

  @type metric_id :: pos_integer()

  # CRUD
  def list_metrics(opts \\ []) do
    Repo.all(from m in Metric, preload: ^Keyword.get(opts, :preload, []))
  end

  def get_metric!(id, opts \\ []) do
    Repo.get!(Metric, id) |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def create_metric(attrs) do
    %Metric{} |> Metric.changeset(attrs) |> Repo.insert()
  end

  def update_metric(%Metric{} = metric, attrs) do
    metric |> Metric.changeset(attrs) |> Repo.update()
  end

  def delete_metric(%Metric{} = metric), do: Repo.delete(metric)

  # Execution
  @doc """
  Run a metric for [from_ts, to_ts) and persist the result. Idempotent by unique index.
  Returns {:ok, %MetricResult{}} or {:error, reason}.
  """
  def run_metric_range(%Metric{} = metric, from_ts, to_ts) do
    with {:ok, value, payload} <- execute_sql(metric, from_ts, to_ts) |> dbg() do
      upsert_result(metric, from_ts, to_ts, value, payload) |> dbg()
    end
  end

  defp upsert_result(metric, from_ts, to_ts, value, payload) do
    changes =
      %{
        metric_id: metric.id,
        from_ts: from_ts,
        to_ts: to_ts,
        value: value,
        payload: payload || %{}
      }
      |> dbg()

    Repo.insert(
      MetricResult.changeset(%MetricResult{}, changes),
      on_conflict: [
        set: [
          value: value,
          payload: payload,
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        ]
      ],
      conflict_target: [:metric_id, :from_ts, :to_ts]
    )
  end

  defp execute_sql(%Metric{server_id: server_id, sql: sql} = _metric, from_ts, to_ts) do
    # Ensure connection and run query via manager
    params =
      if String.contains?(sql, "$1") or String.contains?(sql, "$2") do
        [from_ts, to_ts]
      else
        []
      end

    server = Repo.get!(Server, server_id)

    case QueryCanary.Connections.ConnectionServer.ensure_started(server) do
      {:ok, _pid} ->
        case QueryCanary.Connections.ConnectionServer.query(server_id, sql, params) do
          {:ok, %{rows: rows, columns: [first_col | _]}} when is_list(rows) ->
            parse_rows_from_maps(rows, first_col)

          {:ok, %{rows: rows}} when is_list(rows) ->
            parse_rows(rows)

          {:ok, %Postgrex.Result{} = res} ->
            parse_postgrex_rows(res)

          {:error, reason} ->
            {:error, reason}
        end

      other ->
        other
    end
  end

  defp parse_rows([[val]]) when is_number(val) or is_binary(val),
    do: {:ok, cast_decimal(val), %{}}

  defp parse_rows([[val | _rest]]), do: {:ok, cast_decimal(val), %{}}
  defp parse_rows(_), do: {:error, :unexpected_result_shape}

  defp parse_rows_from_maps([row | _], first_col) when is_map(row) do
    case Map.fetch(row, first_col) do
      {:ok, val} -> {:ok, cast_decimal(val), %{}}
      :error -> {:error, :unexpected_result_shape}
    end
  end

  defp parse_rows_from_maps(_, _), do: {:error, :unexpected_result_shape}

  defp parse_postgrex_rows(%Postgrex.Result{rows: [[val]]}), do: {:ok, cast_decimal(val), %{}}
  defp parse_postgrex_rows(%Postgrex.Result{rows: [[val | _]]}), do: {:ok, cast_decimal(val), %{}}
  defp parse_postgrex_rows(%Postgrex.Result{rows: _}), do: {:error, :unexpected_result_shape}

  defp cast_decimal(val) when is_integer(val), do: Decimal.new(val)
  defp cast_decimal(val) when is_float(val), do: Decimal.from_float(val)
  defp cast_decimal(%Decimal{} = d), do: d

  defp cast_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end

  # ---------------- Backfill helpers ----------------
  @doc """
  Enqueue a bulk backfill job for a metric across a date range (inclusive).
  The range is split into windows based on the metric's granularity.
  """
  def enqueue_backfill(metric_id, %Date{} = from_date, %Date{} = to_date) do
    metric = get_metric!(metric_id)
    tz = metric.timezone || "Etc/UTC"

    from_dt = DateTime.new!(from_date, ~T[00:00:00], tz) |> DateTime.shift_zone!("Etc/UTC")

    to_dt =
      Date.add(to_date, 1)
      |> DateTime.new!(~T[00:00:00], tz)
      |> DateTime.shift_zone!("Etc/UTC")

    %{
      "metric_id" => metric.id,
      "from" => DateTime.to_iso8601(from_dt),
      "to" => DateTime.to_iso8601(to_dt)
    }
    |> QueryCanary.Jobs.MetricBackfillEnqueuer.new()
    |> Oban.insert()
  end

  @doc """
  Build [from, to) windows between two DateTimes using granularity and timezone.
  """
  def windows_for_range(granularity, from_dt, to_dt, tz \\ "Etc/UTC") do
    {start, step_fun} = align_start_and_step(granularity, from_dt, tz)

    Stream.unfold(start, fn cur ->
      if not is_nil(cur) and DateTime.compare(cur, to_dt) in [:lt, :eq] do
        nxt = step_fun.(cur)

        if DateTime.compare(nxt, to_dt) == :gt do
          # {{cur, to_dt}, nil} |> dbg()
          nil
        else
          {{cur, nxt}, nxt} |> dbg()
        end
      else
        nil
      end
    end)
    |> Enum.to_list()
  end

  defp align_start_and_step("minute", from, _tz),
    do: {DateTime.truncate(from, :minute), &DateTime.add(&1, 60, :second)}

  defp align_start_and_step("hour", from, _tz),
    do:
      {%{from | minute: 0, second: 0} |> DateTime.truncate(:second),
       &DateTime.add(&1, 3600, :second)}

  defp align_start_and_step("day", from, tz) do
    {:ok, local} = DateTime.shift_zone(from, tz)
    local_day = Date.new!(local.year, local.month, local.day)
    local_day_start = DateTime.new!(local_day, ~T[00:00:00], tz)
    start = DateTime.shift_zone!(local_day_start, "Etc/UTC")
    {start, fn dt -> DateTime.add(dt, 86_400, :second) end}
  end

  defp align_start_and_step("week", from, tz) do
    {:ok, local} = DateTime.shift_zone(from, tz)
    wday = Date.day_of_week(Date.new!(local.year, local.month, local.day))
    monday = Date.add(Date.new!(local.year, local.month, local.day), -(wday - 1))
    local_week_start = DateTime.new!(monday, ~T[00:00:00], tz)
    start = DateTime.shift_zone!(local_week_start, "Etc/UTC")
    {start, fn dt -> DateTime.add(dt, 7 * 86_400, :second) end}
  end

  defp align_start_and_step("month", from, tz) do
    {:ok, local} = DateTime.shift_zone(from, tz)
    first = Date.new!(local.year, local.month, 1)
    local_month_start = DateTime.new!(first, ~T[00:00:00], tz)
    start = DateTime.shift_zone!(local_month_start, "Etc/UTC")

    step = fn dt ->
      {:ok, local_dt} = DateTime.shift_zone(dt, tz)

      next_first =
        if local_dt.month == 12,
          do: Date.new!(local_dt.year + 1, 1, 1),
          else: Date.new!(local_dt.year, local_dt.month + 1, 1)

      DateTime.new!(next_first, ~T[00:00:00], tz) |> DateTime.shift_zone!("Etc/UTC")
    end

    {start, step}
  end

  defp align_start_and_step(_, from, _tz),
    do: {DateTime.truncate(from, :day), fn dt -> DateTime.add(dt, 86_400, :second) end}
end
