defmodule QueryCanary.Jobs.CheckRunner do
  use Oban.Worker, queue: :checks

  alias QueryCanary.Checks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => check_id} = _args}) do
    check_id
    |> Checks.get_check_for_system!()
    |> Checks.run_check()

    # Need to understand when / how to re-try these?
    :ok
  end
end
