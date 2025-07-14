defmodule QueryCanary.Repo.Migrations.AddSslFieldsToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :db_ssl_mode, :string, default: "allow"
      add :db_ssl_cert, :text
      add :db_ssl_key, :text
      add :db_ssl_ca_cert, :text
    end
  end
end
