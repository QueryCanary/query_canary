defmodule QueryCanary.Metrics.MetricResult do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A stored metric value for a specific time range.
  """

  schema "metric_results" do
    field :from_ts, :utc_datetime
    field :to_ts, :utc_datetime
    field :value, :decimal
    field :payload, :map, default: %{}

    belongs_to :metric, QueryCanary.Metrics.Metric

    timestamps(type: :utc_datetime)
  end

  @required ~w(metric_id from_ts to_ts value)a
  @optional ~w(payload)a

  def changeset(result, attrs) do
    result
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> foreign_key_constraint(:metric_id)
    |> unique_constraint([:metric_id, :from_ts, :to_ts])
  end
end
