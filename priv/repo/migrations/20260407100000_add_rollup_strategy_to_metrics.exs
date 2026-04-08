defmodule QueryCanary.Repo.Migrations.AddRollupStrategyToMetrics do
  use Ecto.Migration

  def change do
    alter table(:metrics) do
      add :rollup_strategy, :string, null: false, default: "sum"
    end
  end
end
