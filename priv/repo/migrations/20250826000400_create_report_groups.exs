defmodule QueryCanary.Repo.Migrations.CreateReportGroups do
  use Ecto.Migration

  def change do
    create table(:report_groups) do
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0
      add :report_id, references(:reports, on_delete: :delete_all), null: false
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:report_groups, [:report_id])
    create unique_index(:report_groups, [:report_id, :name])
  end
end
