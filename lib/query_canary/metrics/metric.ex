defmodule QueryCanary.Metrics.Metric do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A SQL-powered metric definition. The `sql` should accept two parameters: $1 = from_ts, $2 = to_ts.
  Results are stored per time range in metric_results.
  """

  schema "metrics" do
    field :name, :string
    field :sql, :string
    field :description, :string
    field :schedule, :string
    field :granularity, :string, default: "day"
    field :timezone, :string, default: "Etc/UTC"
    field :enabled, :boolean, default: true

    belongs_to :user, QueryCanary.Accounts.User
    belongs_to :team, QueryCanary.Accounts.Team
    belongs_to :server, QueryCanary.Servers.Server

    timestamps(type: :utc_datetime)
  end

  @required ~w(name sql schedule granularity server_id)a
  @optional ~w(description timezone enabled user_id team_id)a

  def changeset(metric, attrs) do
    metric
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, min: 2)
  end
end
