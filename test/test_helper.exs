ExUnit.start(exclude: [:database_adapters])
Ecto.Adapters.SQL.Sandbox.mode(QueryCanary.Repo, :manual)
