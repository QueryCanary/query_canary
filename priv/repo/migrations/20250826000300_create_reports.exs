defmodule QueryCanary.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add :name, :string, null: false
      add :description, :text
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :default_range, :string, null: false, default: "today"
      add :settings, :map, null: false, default: %{}

      add :user_id, references(:users, on_delete: :delete_all)
      add :team_id, references(:teams, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:user_id])
    create index(:reports, [:team_id])

    create constraint(:reports, :reports_owner_present,
             check: """
               (user_id IS NOT NULL)::int + (team_id IS NOT NULL)::int = 1
             """
           )
  end
end
