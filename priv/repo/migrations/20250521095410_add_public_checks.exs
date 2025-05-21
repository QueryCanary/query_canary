defmodule QueryCanary.Repo.Migrations.AddPublicChecks do
  use Ecto.Migration

  def change do
    alter table(:checks) do
      add :public, :boolean, default: false, null: false
    end
  end
end
