defmodule QueryCanary.Reports.ReportGroupMetric do
  use Ecto.Schema
  import Ecto.Changeset

  alias QueryCanary.Metrics.Metric
  alias QueryCanary.Reports.ReportGroup

  schema "report_group_metrics" do
    field :position, :integer, default: 0
    field :settings, :map, default: %{}

    belongs_to :report_group, ReportGroup
    belongs_to :metric, Metric

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(report_group_id metric_id)a
  @optional_fields ~w(position settings)a

  def changeset(group_metric, attrs) do
    group_metric
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:metric_id,
      name: :report_group_metric_unique,
      message: "metric already added to this group"
    )
    |> put_default_settings()
  end

  defp put_default_settings(changeset) do
    update_change(changeset, :settings, fn
      nil -> %{}
      settings -> settings
    end)
  end
end
