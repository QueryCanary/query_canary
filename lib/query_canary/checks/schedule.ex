defmodule QueryCanary.Checks.Schedule do
  @moduledoc "Converts common check schedules to cron and evaluates them in a check's time zone."

  @intervals %{
    "minute" => "* * * * *",
    "5_minutes" => "*/5 * * * *",
    "15_minutes" => "*/15 * * * *",
    "30_minutes" => "*/30 * * * *",
    "hourly" => "0 * * * *"
  }

  @weekdays ~w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

  def options do
    [
      {"Every minute", "minute"},
      {"Every 5 minutes", "5_minutes"},
      {"Every 15 minutes", "15_minutes"},
      {"Every 30 minutes", "30_minutes"},
      {"Every hour", "hourly"},
      {"Every day", "daily"},
      {"Weekdays", "weekdays"},
      {"Every week", "weekly"},
      {"Every month", "monthly"},
      {"Custom cron", "custom"}
    ]
  end

  def weekdays, do: Enum.with_index(@weekdays) |> Enum.map(fn {name, day} -> {name, day} end)
  def monthdays, do: Enum.map(1..28, &{Integer.to_string(&1), &1})

  def from_cron(nil), do: from_cron("0 8 * * *")

  def from_cron(cron) do
    default = %{"kind" => "custom", "time" => "08:00", "weekday" => "1", "monthday" => "1"}

    cond do
      kind =
          Enum.find_value(@intervals, fn {kind, expression} -> if expression == cron, do: kind end) ->
        %{default | "kind" => kind}

      match = Regex.run(~r/^(\d{1,2}) (\d{1,2}) \* \* \*$/, cron) ->
        time_ui(default, "daily", match)

      match = Regex.run(~r/^(\d{1,2}) (\d{1,2}) \* \* 1-5$/, cron) ->
        time_ui(default, "weekdays", match)

      match = Regex.run(~r/^(\d{1,2}) (\d{1,2}) \* \* ([0-6])$/, cron) ->
        [_, minute, hour, weekday] = match
        time_ui(default, "weekly", [nil, minute, hour]) |> Map.put("weekday", weekday)

      match = Regex.run(~r/^(\d{1,2}) (\d{1,2}) (\d{1,2}) \* \*$/, cron) ->
        [_, minute, hour, monthday] = match

        if String.to_integer(monthday) in 1..28 do
          time_ui(default, "monthly", [nil, minute, hour]) |> Map.put("monthday", monthday)
        else
          default
        end

      true ->
        default
    end
  end

  defp time_ui(default, kind, [_, minute, hour]) do
    case Time.new(String.to_integer(hour), String.to_integer(minute), 0) do
      {:ok, _} -> %{default | "kind" => kind, "time" => pad(hour) <> ":" <> pad(minute)}
      _ -> default
    end
  end

  defp pad(value),
    do: value |> String.to_integer() |> Integer.to_string() |> String.pad_leading(2, "0")

  def to_cron(%{"kind" => kind} = ui) do
    cond do
      Map.has_key?(@intervals, kind) ->
        {:ok, Map.fetch!(@intervals, kind)}

      kind in ~w(daily weekdays weekly monthly) ->
        with {:ok, time} <- Time.from_iso8601(Map.get(ui, "time", "") <> ":00") do
          minute = time.minute
          hour = time.hour

          case kind do
            "daily" -> {:ok, "#{minute} #{hour} * * *"}
            "weekdays" -> {:ok, "#{minute} #{hour} * * 1-5"}
            "weekly" -> numbered_cron(ui["weekday"], 0..6, "#{minute} #{hour} * * ")
            "monthly" -> numbered_cron(ui["monthday"], 1..28, "#{minute} #{hour} ", " * *")
          end
        else
          _ -> {:error, "Choose a valid time"}
        end

      true ->
        {:error, "Choose a schedule"}
    end
  end

  defp numbered_cron(value, range, prefix, suffix \\ "") do
    case Integer.parse(to_string(value)) do
      {number, ""} ->
        if number in range,
          do: {:ok, prefix <> Integer.to_string(number) <> suffix},
          else: {:error, "Choose a valid day"}

      _ ->
        {:error, "Choose a valid day"}
    end
  end

  def description(cron, timezone) do
    ui = from_cron(cron)
    kind = ui["kind"]

    case kind do
      "minute" ->
        "Every minute"

      "5_minutes" ->
        "Every 5 minutes"

      "15_minutes" ->
        "Every 15 minutes"

      "30_minutes" ->
        "Every 30 minutes"

      "hourly" ->
        "Every hour"

      "daily" ->
        "Every day at #{display_time(ui)} (#{timezone})"

      "weekdays" ->
        "Weekdays at #{display_time(ui)} (#{timezone})"

      "weekly" ->
        "Every #{Enum.at(@weekdays, String.to_integer(ui["weekday"]))} at #{display_time(ui)} (#{timezone})"

      "monthly" ->
        "Day #{ui["monthday"]} of each month at #{display_time(ui)} (#{timezone})"

      _ ->
        "Custom cron: #{cron} (#{timezone})"
    end
  end

  defp display_time(ui) do
    {:ok, time} = Time.from_iso8601(ui["time"] <> ":00")
    Calendar.strftime(time, "%-I:%M %p")
  end

  def matches?(cron, timezone, %DateTime{} = utc_now) do
    with {:ok, expression} <- Crontab.CronExpression.Parser.parse(cron),
         {:ok, local} <- DateTime.shift_zone(utc_now, timezone) do
      Crontab.DateChecker.matches_date?(expression, local) and
        not repeated_calendar_time?(cron, local)
    else
      _ -> false
    end
  end

  def next_runs(cron, timezone, now \\ DateTime.utc_now(), count \\ 3) do
    with {:ok, expression} <- Crontab.CronExpression.Parser.parse(cron),
         {:ok, local_now} <- DateTime.shift_zone(now, timezone) do
      # Start before the current local hour so a repeated DST hour is included.
      start_at = local_now |> DateTime.to_naive() |> NaiveDateTime.add(-7200, :second)
      boundary = local_now |> DateTime.to_naive() |> NaiveDateTime.add(10_800, :second)

      expression
      |> Crontab.Scheduler.get_next_run_dates(start_at)
      |> candidates_through(boundary, count, now, timezone, cron)
      |> Enum.sort(&(DateTime.compare(&1, &2) != :gt))
      |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
      |> Enum.take(count)
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp candidates_through(stream, boundary, count, now, timezone, cron) do
    {runs, _} =
      Enum.reduce_while(stream, {[], 0}, fn candidate, {acc, future_count} ->
        resolved = resolve_local_time(candidate, timezone, cron)
        future_count = future_count + Enum.count(resolved, &(DateTime.compare(&1, now) == :gt))
        acc = Enum.reverse(resolved, acc)

        if NaiveDateTime.compare(candidate, boundary) == :gt and future_count >= count do
          {:halt, {acc, future_count}}
        else
          {:cont, {acc, future_count}}
        end
      end)

    Enum.reverse(runs)
  end

  defp resolve_local_time(naive, timezone, cron) do
    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} ->
        [datetime]

      {:ambiguous, first, second} ->
        if calendar_schedule?(cron), do: [first], else: [first, second]

      {:gap, _, _} ->
        []

      _ ->
        []
    end
  end

  defp repeated_calendar_time?(cron, local) do
    calendar_schedule?(cron) and
      case DateTime.from_naive(DateTime.to_naive(local), local.time_zone) do
        {:ambiguous, _first, second} -> DateTime.compare(local, second) == :eq
        _ -> false
      end
  end

  defp calendar_schedule?(cron), do: from_cron(cron)["kind"] in ~w(daily weekdays weekly monthly)
end
