defmodule QueryCanary.Accounts.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string

    has_many :team_users, QueryCanary.Accounts.TeamUser
    has_many :users, QueryCanary.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs, user_scope) do
    team
    |> cast(attrs, [:name])
    |> validate_required([:name])

    # |> put_change(:user_id, user_scope.user.id)
  end
end
