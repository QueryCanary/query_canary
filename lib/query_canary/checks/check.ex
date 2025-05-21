defmodule QueryCanary.Checks.Check do
  use Ecto.Schema
  import Ecto.Changeset

  schema "checks" do
    field :name, :string
    field :schedule, :string
    field :enabled, :boolean, default: false
    field :query, :string
    field :expectation, :map
    field :public, :boolean, default: false

    belongs_to :server, QueryCanary.Servers.Server
    belongs_to :user, QueryCanary.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(check, attrs, user_scope) do
    check
    |> cast(attrs, [:name, :schedule, :enabled, :query, :server_id, :public])
    |> validate_required([:name, :schedule, :enabled, :query, :server_id])
    |> validate_cron_expression(:schedule)
    |> foreign_key_constraint(:server_id)
    |> put_change(:user_id, user_scope.user.id)
  end

  defp validate_cron_expression(changeset, field) do
    validate_change(changeset, field, fn _, raw_exp ->
      if raw_exp in ["", nil] do
        []
      else
        case CronExpression.Parser.parse(raw_exp) do
          {:ok, _} -> []
          {:error, message} -> [{field, message}]
        end
      end
    end)
  end
end
