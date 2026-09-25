defmodule QueryCanary.Repo.Migrations.AddCheckTimezone do
  use Ecto.Migration

  def change do
    alter table(:checks) do
      add :timezone, :string, null: false, default: "Etc/UTC"
    end
  end
end
