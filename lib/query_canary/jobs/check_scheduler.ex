defmodule QueryCanary.Jobs.CheckScheduler do
  use Oban.Worker, queue: :default

  require Logger

  alias QueryCanary.Jobs.CheckRunner
  alias QueryCanary.Checks.Schedule

  @impl Oban.Worker
  def perform(_) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Logger.info("Cron tick at #{now}")

    enabled_checks = QueryCanary.Checks.list_enabled_checks_for_everyone()

    Enum.each(enabled_checks, fn check ->
      if Schedule.matches?(check.schedule, check.timezone || "Etc/UTC", now) do
        Logger.info("Scheduling check #{check.name} at #{now}")

        %{"id" => check.id}
        |> CheckRunner.new()
        |> Oban.insert()
      end
    end)

    :ok
  end
end
