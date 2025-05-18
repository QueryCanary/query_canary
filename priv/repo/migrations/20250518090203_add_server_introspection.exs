defmodule QueryCanary.Repo.Migrations.AddServerIntrospection do
  use Ecto.Migration

  def change do
    alter table(:servers) do
      add :schema, :jsonb
    end
  end
end
