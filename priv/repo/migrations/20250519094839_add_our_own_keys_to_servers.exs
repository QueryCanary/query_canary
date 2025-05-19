defmodule QueryCanary.Repo.Migrations.AddOurOwnKeysToServers do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      remove :ssh_password

      add :ssh_public_key, :text, after: :ssh_port
      add :ssh_key_type, :string
      add :ssh_key_generated_at, :utc_datetime
    end
  end
end
