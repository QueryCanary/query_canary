defmodule QueryCanary.Jobs.DeliverNotification do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 10,
    unique: [
      period: :infinity,
      keys: [:destination_id, :check_result_id],
      states: [:available, :scheduled, :executing, :retryable, :completed, :discarded, :cancelled]
    ]

  alias QueryCanary.Repo
  alias QueryCanary.Notifications
  alias QueryCanary.Notifications.{Alert, Chart, Destination, Integration}
  alias QueryCanary.Checks.CheckResult

  @impl true
  def perform(%Oban.Job{
        args: %{"destination_id" => destination_id, "check_result_id" => result_id}
      }) do
    with %Destination{} = destination <- Repo.get(Destination, destination_id),
         %CheckResult{is_alert: true} = result <- Repo.get(CheckResult, result_id),
         true <- result.check_id == destination.check_id,
         destination <- Repo.preload(destination, [:integration, check: :server]),
         true <- destination.integration.team_id == destination.check.server.team_id,
         :ok <- notification_enabled(destination),
         {:ok, adapter} <- Map.fetch(Notifications.providers(), destination.integration.provider),
         {:ok, token} <- Integration.token(destination.integration) do
      alert = Alert.from_result(destination.check, result)
      history = QueryCanary.Checks.get_results_through(result)
      alert = %{alert | chart: Chart.render(destination.check, history)}

      case adapter.deliver(token, destination.channel_id, alert) do
        :ok ->
          :ok

        {:error, {:rate_limited, seconds}} ->
          {:snooze, seconds}

        {:error, reason} when reason in [:unauthorized, :missing_scope, :invalid_destination] ->
          {:cancel, reason}

        {:error, _} = error ->
          error
      end
    else
      # Deleted/disconnected destinations, moved servers, and removed results must not send.
      nil -> {:cancel, :removed}
      false -> {:cancel, :destination_changed}
      %CheckResult{} -> {:cancel, :not_an_alert}
      {:error, :notifications_disabled} -> {:cancel, :notifications_disabled}
      _ -> {:cancel, :invalid_connection}
    end
  end

  defp notification_enabled(destination) do
    if Notifications.enabled?(destination.check, destination.integration.provider),
      do: :ok,
      else: {:error, :notifications_disabled}
  end
end
