defmodule QueryCanary.Checks.CheckAnalysis do
  use Ecto.Schema
  import Ecto.Changeset
  alias QueryCanary.Checks.Check
  alias QueryCanary.Checks.CheckResult

  schema "check_analyses" do
    field :alert_type, Ecto.Enum, values: [:diff, :anomaly, :failure, :none]
    field :is_alert, :boolean, default: false
    field :details, :map
    field :summary, :string

    # When this analysis was created
    field :analyzed_at, :utc_datetime

    belongs_to :check, Check
    belongs_to :check_result, CheckResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(check_analysis, attrs) do
    check_analysis
    |> cast(attrs, [
      :alert_type,
      :is_alert,
      :details,
      :summary,
      :analyzed_at,
      :check_id,
      :check_result_id
    ])
    |> validate_required([:alert_type, :is_alert, :analyzed_at, :check_id, :check_result_id])
  end
end
