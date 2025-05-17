defmodule QueryCanary.Repo.Migrations.CreateCheckResults do
  use Ecto.Migration

  def change do
    create table(:check_results) do
      add :success, :boolean, default: false, null: false
      add :error, :text
      add :result, :jsonb
      add :time_taken, :integer
      add :check_id, references(:checks, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:check_results, [:check_id])
  end
end
