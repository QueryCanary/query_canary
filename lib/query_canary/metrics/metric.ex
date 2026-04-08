defmodule QueryCanary.Metrics.Metric do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A SQL-powered metric definition. The `sql` should accept two parameters: $1 = from_ts, $2 = to_ts.
  Results are stored per time range in metric_results.
  """

  @default_schedule "0 8 * * *"

  schema "metrics" do
    field :name, :string
    field :sql, :string
    field :description, :string
    field :schedule, :string
    field :granularity, :string, default: "day"
    field :rollup_strategy, :string, default: "sum"
    field :timezone, :string, default: "Etc/UTC"
    field :enabled, :boolean, default: true

    belongs_to :user, QueryCanary.Accounts.User
    belongs_to :team, QueryCanary.Accounts.Team
    belongs_to :server, QueryCanary.Servers.Server

    timestamps(type: :utc_datetime)
  end

  @required ~w(name sql granularity server_id)a
  @optional ~w(description schedule timezone enabled user_id team_id)a
  @granularities ~w(minute hour day week month)
  @rollup_strategies ~w(sum last)

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, @required ++ @optional ++ [:rollup_strategy])
    |> put_default_schedule()
    |> validate_required(@required)
    |> validate_length(:name, min: 2)
    |> validate_inclusion(:granularity, @granularities)
    |> validate_inclusion(:rollup_strategy, @rollup_strategies)
  end

  defp put_default_schedule(changeset) do
    case get_field(changeset, :schedule) do
      nil -> put_change(changeset, :schedule, @default_schedule)
      "" -> put_change(changeset, :schedule, @default_schedule)
      _ -> changeset
    end
  end
end
