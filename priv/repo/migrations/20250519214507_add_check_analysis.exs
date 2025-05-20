defmodule QueryCanary.Repo.Migrations.CreateCheckAnalyses do
  use Ecto.Migration

  def change do
    alter table(:check_results) do
      add :is_alert, :boolean, null: false, default: false
      add :alert_type, :string, null: false, default: "none"
      add :analysis_details, :map
      add :analysis_summary, :string
    end
  end
end
