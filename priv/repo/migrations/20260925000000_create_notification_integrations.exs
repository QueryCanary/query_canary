defmodule QueryCanary.Repo.Migrations.CreateNotificationIntegrations do
  use Ecto.Migration

  def change do
    create table(:notification_integrations) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :external_id, :string, null: false
      add :name, :string, null: false
      add :encrypted_token, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_integrations, [:team_id, :provider])

    create table(:notification_destinations) do
      add :check_id, references(:checks, on_delete: :delete_all), null: false

      add :integration_id, references(:notification_integrations, on_delete: :delete_all),
        null: false

      add :channel_id, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_destinations, [:check_id, :integration_id])
    create index(:notification_destinations, [:integration_id])
  end
end
