defmodule QueryCanary.Accounts.TeamUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_users" do
    field :role, Ecto.Enum, values: [:admin, :member, :invited]

    belongs_to :team, QueryCanary.Accounts.Team
    belongs_to :user, QueryCanary.Accounts.User
  end

  @doc false
  def changeset(team_user, attrs) do
    team_user
    |> cast(attrs, [:team_id, :user_id, :role])
    |> validate_required([:team_id, :user_id, :role])
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:user_id)
  end
end
