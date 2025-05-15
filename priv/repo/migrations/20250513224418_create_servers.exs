defmodule QueryCanary.Repo.Migrations.CreateServers do
  use Ecto.Migration

  def change do
    create table(:servers) do
      add :name, :string, null: false

      add :db_engine, :string, null: false
      add :db_hostname, :string, null: false
      add :db_port, :integer, null: false
      add :db_name, :string, null: false
      add :db_username, :string, null: false
      add :db_password, :text, null: false

      add :ssh_tunnel, :boolean
      add :ssh_hostname, :string
      add :ssh_username, :string
      add :ssh_port, :integer
      add :ssh_password, :text
      add :ssh_private_key, :text

      add :user_id, references(:users, type: :id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:servers, [:user_id])
  end
end
