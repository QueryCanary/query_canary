defmodule QueryCanary.Accounts.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string

    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :plan, Ecto.Enum, values: [:free, :paid]
    field :billing_status, :string
    field :billing_started_at, :utc_datetime
    field :billing_renewal_at, :utc_datetime

    has_many :team_users, QueryCanary.Accounts.TeamUser
    # has_many :users, QueryCanary.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs, _user_scope) do
    team
    |> cast(attrs, [:name])
    |> validate_required([:name])

    # |> put_change(:user_id, user_scope.user.id)
  end

  def stripe_changeset(team, attrs) do
    fields = [
      :stripe_customer_id,
      :stripe_subscription_id,
      :plan,
      :billing_status,
      :billing_started_at,
      :billing_renewal_at
    ]

    team
    |> cast(attrs, fields)
    |> validate_required(fields)
  end
end
