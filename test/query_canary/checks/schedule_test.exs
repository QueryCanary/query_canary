defmodule QueryCanary.Checks.ScheduleTest do
  use ExUnit.Case, async: true

  alias QueryCanary.Checks.Schedule

  test "common schedules round trip through cron" do
    for {kind, expected} <- [
          {"minute", "* * * * *"},
          {"5_minutes", "*/5 * * * *"},
          {"hourly", "0 * * * *"},
          {"daily", "30 9 * * *"},
          {"weekdays", "30 9 * * 1-5"},
          {"weekly", "30 9 * * 2"},
          {"monthly", "30 9 1 * *"}
        ] do
      ui = %{"kind" => kind, "time" => "09:30", "weekday" => "2", "monthday" => "1"}
      assert {:ok, ^expected} = Schedule.to_cron(ui)
      assert Schedule.from_cron(expected)["kind"] == kind
    end

    assert Schedule.from_cron("7 13 * * 2,4")["kind"] == "custom"

    assert {:error, _} =
             Schedule.to_cron(%{"kind" => "monthly", "time" => "09:30", "monthday" => "31"})
  end

  test "daily local time follows summer and winter offsets" do
    cron = "0 9 * * *"
    zone = "America/New_York"

    assert Schedule.matches?(cron, zone, ~U[2026-01-15 14:00:00Z])
    refute Schedule.matches?(cron, zone, ~U[2026-01-15 13:00:00Z])
    assert Schedule.matches?(cron, zone, ~U[2026-07-15 13:00:00Z])
    refute Schedule.matches?(cron, zone, ~U[2026-07-15 14:00:00Z])
  end

  test "a skipped local time does not appear in the preview" do
    [first, second, third] =
      Schedule.next_runs("30 2 * * *", "America/New_York", ~U[2026-03-08 00:00:00Z])

    assert DateTime.shift_zone!(first, "Etc/UTC") == ~U[2026-03-09 06:30:00Z]
    assert DateTime.shift_zone!(second, "Etc/UTC") == ~U[2026-03-10 06:30:00Z]
    assert DateTime.shift_zone!(third, "Etc/UTC") == ~U[2026-03-11 06:30:00Z]
  end

  test "a repeated daily time runs once, while intervals keep running" do
    zone = "America/New_York"
    first = ~U[2026-11-01 05:30:00Z]
    second = ~U[2026-11-01 06:30:00Z]

    assert Schedule.matches?("30 1 * * *", zone, first)
    refute Schedule.matches?("30 1 * * *", zone, second)
    assert Schedule.matches?("*/30 * * * *", zone, first)
    assert Schedule.matches?("*/30 * * * *", zone, second)

    [next, later | _] = Schedule.next_runs("30 1 * * *", zone, ~U[2026-11-01 04:00:00Z])
    assert DateTime.shift_zone!(next, "Etc/UTC") == first
    assert DateTime.shift_zone!(later, "Etc/UTC") == ~U[2026-11-02 06:30:00Z]

    [interval_first, interval_second | _] =
      Schedule.next_runs("* * * * *", zone, ~U[2026-11-01 05:29:00Z])

    assert DateTime.shift_zone!(interval_first, "Etc/UTC") == ~U[2026-11-01 05:30:00Z]
    assert DateTime.shift_zone!(interval_second, "Etc/UTC") == ~U[2026-11-01 05:31:00Z]
  end
end
