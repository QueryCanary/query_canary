defmodule QueryCanary.Repo.Migrations.CreateMetrics do
  use Ecto.Migration

  def change do
    create table(:metrics) do
      add :name, :string, null: false
      add :description, :text
      add :sql, :text, null: false
      add :schedule, :string, null: false
      add :granularity, :string, null: false, default: "day"
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :enabled, :boolean, null: false, default: true

      add :user_id, references(:users, on_delete: :nilify_all)
      add :team_id, references(:teams, on_delete: :nilify_all)
      add :server_id, references(:servers, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:metrics, [:server_id])
    create index(:metrics, [:user_id])
    create index(:metrics, [:team_id])
  end
end
