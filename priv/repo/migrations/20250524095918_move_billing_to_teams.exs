defmodule QueryCanary.Repo.Migrations.MoveBillingToTeams do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :stripe_customer_id
      remove :stripe_subscription_id
      remove :plan
      remove :billing_status
      remove :billing_started_at
    end

    alter table(:teams) do
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :plan, :string, default: "free"
      add :billing_status, :string
      add :billing_started_at, :utc_datetime_usec
      add :billing_renewal_at, :utc_datetime_usec
    end

    create index(:teams, [:stripe_subscription_id])
  end
end
