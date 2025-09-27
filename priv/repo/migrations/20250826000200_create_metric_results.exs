defmodule QueryCanary.Repo.Migrations.CreateMetricResults do
  use Ecto.Migration

  def change do
    create table(:metric_results) do
      add :metric_id, references(:metrics, on_delete: :delete_all), null: false
      add :from_ts, :utc_datetime, null: false
      add :to_ts, :utc_datetime, null: false
      add :value, :decimal, null: false
      add :payload, :map

      timestamps(type: :utc_datetime)
    end

    create index(:metric_results, [:metric_id])
    create unique_index(:metric_results, [:metric_id, :from_ts, :to_ts])
  end
end
