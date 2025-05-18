defmodule QueryCanary.Jobs.CheckScheduler do
  use Oban.Worker, queue: :default

  require Logger

  alias Crontab.CronExpression
  alias QueryCanary.Jobs.CheckRunner

  @impl Oban.Worker
  def perform(_) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Logger.info("Cron tick at #{now}")

    enabled_checks = QueryCanary.Checks.list_enabled_checks_for_everyone()

    Enum.each(enabled_checks, fn check ->
      case CronExpression.Parser.parse(check.schedule) do
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

    :ok
  end
end
