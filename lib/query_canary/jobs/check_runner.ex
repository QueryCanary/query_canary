defmodule QueryCanary.Jobs.CheckRunner do
  use Oban.Worker,
    queue: :checks,
    max_attempts: 1

  alias QueryCanary.Checks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => check_id} = _args}) do
    case check_id |> Checks.get_check_for_system!() |> Checks.run_check() do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
