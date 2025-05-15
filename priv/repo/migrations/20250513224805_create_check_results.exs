defmodule QueryCanary.Repo.Migrations.CreateCheckResults do
  use Ecto.Migration

  def change do
    create table(:check_results) do
      add :success, :boolean, default: false, null: false
      add :result, :text
      add :time_taken, :integer
      add :check_id, references(:checks, on_delete: :nothing)
      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:check_results, [:user_id])

    create index(:check_results, [:check_id])
  end
end
