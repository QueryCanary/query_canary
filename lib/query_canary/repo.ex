defmodule QueryCanary.Repo do
  use Ecto.Repo,
    otp_app: :query_canary,
    adapter: Ecto.Adapters.Postgres
end
