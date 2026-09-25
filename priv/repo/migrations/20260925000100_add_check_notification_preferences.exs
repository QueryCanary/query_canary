defmodule QueryCanary.Repo.Migrations.AddCheckNotificationPreferences do
  use Ecto.Migration

  def change do
    alter table(:checks) do
      # Missing provider keys mean enabled, preserving existing alert behavior.
      add :notification_preferences, :map, null: false, default: %{}
    end
  end
end
