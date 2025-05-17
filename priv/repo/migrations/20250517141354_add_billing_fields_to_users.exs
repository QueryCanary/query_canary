defmodule QueryCanary.Repo.Migrations.AddBillingFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :plan, :string, default: "free"
      add :billing_status, :string
      add :billing_started_at, :utc_datetime_usec
    end

    create index(:users, [:stripe_customer_id])
    create index(:users, [:stripe_subscription_id])
  end
end
