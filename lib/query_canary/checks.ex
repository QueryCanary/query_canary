defmodule QueryCanary.Checks do
  @moduledoc """
  The Checks context.
  """

  import Ecto.Query, warn: false
  alias QueryCanary.CheckResultAnalyzer
  alias QueryCanary.Repo

  alias QueryCanary.Checks.{Check, CheckResult}
  alias QueryCanary.Accounts.Scope
  alias QueryCanary.Connections.ConnectionManager
  alias QueryCanary.Checks.CheckNotifier

  @doc """
  Subscribes to scoped notifications about any check changes.

  The broadcasted messages match the pattern:

    * {:created, %Check{}}
    * {:updated, %Check{}}
    * {:deleted, %Check{}}

  """
  def subscribe_checks(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(QueryCanary.PubSub, "user:#{key}:checks")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(QueryCanary.PubSub, "user:#{key}:checks", message)
  end

  @doc """
  Returns the list of checks.

  ## Examples

      iex> list_checks(scope)
      [%Check{}, ...]

  """
  def list_checks(%Scope{} = scope) do
    Repo.all(from check in Check, where: check.user_id == ^scope.user.id) |> Repo.preload(:server)
  end

  @doc """
  Gets a single check.

  Raises `Ecto.NoResultsError` if the Check does not exist.

  ## Examples

      iex> get_check!(123)
      %Check{}

      iex> get_check!(456)
      ** (Ecto.NoResultsError)

  """
  def get_check!(%Scope{} = scope, id) do
    Repo.get_by!(Check, id: id, user_id: scope.user.id)
    |> Repo.preload(:server)
  end

  def get_check(%Scope{} = scope, id) do
    Repo.get_by(Check, id: id, user_id: scope.user.id)
    |> Repo.preload(:server)
  end

  def get_check_for_system!(id) do
    Repo.get_by!(Check, id: id)
    |> Repo.preload(:server)
  end

  @doc """
  Creates a check.

  ## Examples

      iex> create_check(%{field: value})
      {:ok, %Check{}}

      iex> create_check(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_check(%Scope{} = scope, attrs) do
    with {:ok, check = %Check{}} <-
           %Check{}
           |> Check.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast(scope, {:created, check})
      {:ok, check}
    end
  end

  @doc """
  Updates a check.

  ## Examples

      iex> update_check(check, %{field: new_value})
      {:ok, %Check{}}

      iex> update_check(check, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_check(%Scope{} = scope, %Check{} = check, attrs) do
    true = check.user_id == scope.user.id

    with {:ok, check = %Check{}} <-
           check
           |> Check.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, check})
      {:ok, check}
    end
  end

  @doc """
  Deletes a check.

  ## Examples

      iex> delete_check(check)
      {:ok, %Check{}}

      iex> delete_check(check)
      {:error, %Ecto.Changeset{}}

  """
  def delete_check(%Scope{} = scope, %Check{} = check) do
    true = check.user_id == scope.user.id

    with {:ok, check = %Check{}} <-
           Repo.delete(check) do
      broadcast(scope, {:deleted, check})
      {:ok, check}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking check changes.

  ## Examples

      iex> change_check(check)
      %Ecto.Changeset{data: %Check{}}

  """
  def change_check(%Scope{} = scope, %Check{} = check, attrs \\ %{}) do
    true = check.user_id == scope.user.id

    Check.changeset(check, attrs, scope)
  end

  def list_checks_by_server(%Scope{} = scope, server_id) do
    Repo.all(
      from c in Check,
        where: c.user_id == ^scope.user.id and c.server_id == ^server_id,
        order_by: [desc: c.updated_at]
    )
  end

  def list_enabled_checks_for_everyone do
    Repo.all(from c in Check, where: c.enabled == true)
  end

  @doc """
  Runs a specific check and records the result.

  ## Parameters
    * check - The check to run
    * scope - The user scope for authorization

  ## Returns
    * {:ok, %CheckResult{}} - Check completed and result saved
    * {:error, reason} - Check failed to run or save
  """
  def run_check(%Check{} = check) do
    check = Repo.preload(check, :server)
    start_time = System.monotonic_time(:millisecond)

    # Run the query using the ConnectionManager
    result =
      try do
        case ConnectionManager.run_query(check.server, check.query) do
          {:ok, %{rows: rows}} ->
            # Calculate time taken
            end_time = System.monotonic_time(:millisecond)
            time_taken = end_time - start_time

            # Build successful result
            %{
              success: true,
              result: rows,
              time_taken: time_taken,
              check_id: check.id
            }

          {:error, error} ->
            # Calculate time taken
            end_time = System.monotonic_time(:millisecond)
            time_taken = end_time - start_time

            # Build error result
            %{
              success: false,
              result: %{},
              error: "#{inspect(error)}",
              time_taken: time_taken,
              check_id: check.id
            }
        end
      rescue
        e ->
          # Handle any exceptions
          end_time = System.monotonic_time(:millisecond)
          time_taken = end_time - start_time

          # Build error result for exception
          %{
            success: false,
            result: %{},
            error: "Exception: #{inspect(e)}",
            time_taken: time_taken,
            check_id: check.id
          }
      end

    # Save the check result
    case create_check_result(result) do
      {:ok, check_result} ->
        # Run analysis on the new result
        recent_results = get_recent_check_results(check, 20)

        analysis = CheckResultAnalyzer.analyze_results(recent_results)
        {alert_type, is_alert, details, summary} = format_analysis_result(analysis)

        # Update the check result with analysis data
        {:ok, updated_result} =
          update_check_result(check_result, %{
            alert_type: alert_type,
            is_alert: is_alert,
            analysis_details: details,
            analysis_summary: summary
          })

        # Send notification if this is an alert
        maybe_send_check_notification(check, updated_result)

        {:ok, updated_result}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a check result.

  ## Parameters
    * scope - The user scope for authorization
    * attrs - Attributes for the check result

  ## Returns
    * {:ok, %CheckResult{}} - Result created successfully
    * {:error, changeset} - Failed to create result
  """
  def create_check_result(attrs) do
    %CheckResult{}
    |> CheckResult.changeset(attrs)
    |> Repo.insert()
  end

  def update_check_result(%CheckResult{} = check_result, attrs) do
    with {:ok, check_result = %CheckResult{}} <-
           check_result
           |> CheckResult.changeset(attrs)
           |> Repo.update() do
      # broadcast(scope, {:updated, check})
      {:ok, check_result}
    end
  end

  @doc """
  Gets the most recent results for a check.

  ## Parameters
    * scope - The user scope for authorization
    * check_id - The ID of the check to get results for
    * limit - Maximum number of results to return (default: 10)

  ## Returns
    * [%CheckResult{}] - List of check results, newest first
  """
  def get_recent_check_results(%Check{id: check_id}, limit \\ 10) do
    Repo.all(
      from r in CheckResult,
        where: r.check_id == ^check_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Returns the list of checks with their status information.
  This includes the last result, last run time, and alert status.

  ## Parameters
    * scope - The user scope for authorization

  ## Returns
    * [%{check: %Check{}, last_result: %CheckResult{}, last_run_at: DateTime.t(), alert_status: String.t()}]
  """
  def list_checks_with_status(%Scope{} = scope) do
    # First get all checks for this scope
    checks = list_checks(scope)

    # For each check, get the latest result and analyze status
    Enum.map(checks, fn check ->
      # Get the most recent results (limit to what we need for analysis)
      recent_results = get_recent_check_results(check, 1)

      # Get the most recent result (if any)
      last_result = List.first(recent_results)
      last_run_at = if last_result, do: last_result.inserted_at, else: nil

      # Return a map with all the check data enriched with status info
      Map.merge(check, %{
        last_result: last_result,
        recent_results: recent_results,
        last_run_at: last_run_at
      })
    end)
  end

  # Format the analysis result for storage
  defp format_analysis_result({:ok, nil}) do
    {:none, false, %{}, "No issues detected"}
  end

  defp format_analysis_result({:alert, %{type: type, details: details}})
       when type in [:diff, :anomaly] do
    # Create a human-readable summary from the details
    summary = details.message || "#{String.capitalize(to_string(type))} detected"

    {type, true, details, summary}
  end

  defp format_analysis_result({:error, reason}) do
    {:none, false, %{error: reason}, "Analysis failed: #{inspect(reason)}"}
  end

  @doc """
  Sends a notification for a check alert if needed.

  ## Parameters
    * check - The check that may have triggered an alert
    * check_result - The check result to analyze for alerts

  ## Returns
    * {:ok, :notification_sent} - Notification was sent
    * {:ok, :no_alert} - No alert detected, no notification needed
    * {:error, reason} - Error sending notification
  """
  def maybe_send_check_notification(%Check{} = check, %CheckResult{} = check_result) do
    if check_result.is_alert do
      # Only send notifications for actual alerts
      check = Repo.preload(check, :user)
      url = QueryCanaryWeb.Endpoint.url() <> "/checks/#{check.id}"

      CheckNotifier.deliver_check_alert_notification(
        check.user,
        check,
        check_result,
        url
      )
    else
      {:ok, :no_alert}
    end
  end
end
