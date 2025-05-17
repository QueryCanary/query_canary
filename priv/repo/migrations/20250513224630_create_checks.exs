defmodule QueryCanary.Repo.Migrations.CreateChecks do
  use Ecto.Migration

  def change do
    create table(:checks) do
      add :name, :string
      add :schedule, :string
      add :enabled, :boolean
      add :query, :text
      add :expectation, :json
      add :server_id, references(:servers, on_delete: :nothing)
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:checks, [:user_id])

    create index(:checks, [:server_id])
  end
end
