defmodule QueryCanary.Checks.Check do
  use Ecto.Schema
  import Ecto.Changeset

  schema "checks" do
    field :query, :string
    field :expectation, :string

    belongs_to :server, QueryCanary.Servers.Server
    belongs_to :user, QueryCanary.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(check, attrs, user_scope) do
    check
    |> cast(attrs, [:query, :expectation, :server_id])
    |> validate_required([:query, :server_id])
    |> foreign_key_constraint(:server_id)
    |> put_change(:user_id, user_scope.user.id)
  end
end
