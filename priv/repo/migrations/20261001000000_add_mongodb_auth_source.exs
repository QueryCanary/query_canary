defmodule QueryCanary.Repo.Migrations.AddMongodbAuthSource do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :db_auth_source, :string
    end
  end
end
