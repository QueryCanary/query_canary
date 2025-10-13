defmodule QueryCanary.Reports.ReportGroup do
  use Ecto.Schema
  import Ecto.Changeset

  alias QueryCanary.Reports.{Report, ReportGroupMetric}

  schema "report_groups" do
    field :name, :string
    field :position, :integer, default: 0
    field :settings, :map, default: %{}

    belongs_to :report, Report
    has_many :group_metrics, ReportGroupMetric

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name report_id)a
  @optional_fields ~w(position settings)a

  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2)
    |> put_default_settings()
  end

  defp put_default_settings(changeset) do
    update_change(changeset, :settings, fn
      nil -> %{}
      settings -> settings
    end)
  end
end
