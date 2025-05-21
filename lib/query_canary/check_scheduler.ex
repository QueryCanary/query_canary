defmodule QueryCanary.CheckScheduler do
  use GenServer

  alias QueryCanary.Jobs.CheckRunner

  require Logger

  @tick_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_) do
    send(self(), :tick)
    {:ok, nil}
  end

  def handle_info(:tick, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Logger.info("Cron tick at #{now}")

    enabled_checks = QueryCanary.Checks.list_enabled_checks_for_everyone()

    Enum.each(enabled_checks, fn check ->
      case Crontab.CronExpression.Parser.parse(check.schedule) do
        {:ok, expr} ->
          if Crontab.DateChecker.matches_date?(expr, now) do
            Logger.info("Scheduling check #{check.name} at #{now}")

            %{"id" => check.id}
            |> CheckRunner.new()
            |> Oban.insert()
          end

        {:error, reason} ->
          Logger.warning("Invalid cron: #{check.schedule} (#{reason})")
      end
    end)

    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
end
