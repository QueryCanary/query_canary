defmodule QueryCanary.Repo.Migrations.CreateReportGroupMetrics do
  use Ecto.Migration

  def change do
    create table(:report_group_metrics) do
      add :position, :integer, null: false, default: 0
      add :settings, :map, null: false, default: %{}

      add :report_group_id, references(:report_groups, on_delete: :delete_all), null: false
      add :metric_id, references(:metrics, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:report_group_metrics, [:report_group_id])
    create index(:report_group_metrics, [:metric_id])

    create unique_index(:report_group_metrics, [:report_group_id, :metric_id],
             name: :report_group_metric_unique
           )
  end
end
