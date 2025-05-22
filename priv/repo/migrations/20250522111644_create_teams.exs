defmodule QueryCanary.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create table(:team_users) do
      add :team_id, references(:teams, type: :id, on_delete: :delete_all)
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      add :role, :string
    end

    alter table(:servers) do
      add :team_id, references(:teams, type: :id, on_delete: :delete_all), null: true
    end
  end
end
