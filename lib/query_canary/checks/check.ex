defmodule QueryCanary.Checks.Check do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias QueryCanary.Accounts.TeamUser
  alias QueryCanary.Servers.Server

  schema "checks" do
    field :name, :string
    field :schedule, :string
    field :enabled, :boolean, default: false
    field :query, :string
    field :expectation, :map
    field :public, :boolean, default: false

    belongs_to :server, QueryCanary.Servers.Server
    belongs_to :user, QueryCanary.Accounts.User

    has_many :results, QueryCanary.Checks.CheckResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(check, attrs, user_scope) do
    check
    |> cast(attrs, [:name, :schedule, :enabled, :query, :server_id, :public])
    |> validate_required([:name, :schedule, :enabled, :query, :server_id])
    |> validate_cron_expression(:schedule)
    |> foreign_key_constraint(:server_id)
    |> validate_server_id_unchanged()
    |> validate_server_access(user_scope)
    |> put_user_id_on_insert(user_scope)
  end

  defp validate_cron_expression(changeset, field) do
    validate_change(changeset, field, fn _, raw_exp ->
      if raw_exp in ["", nil] do
        []
      else
        case Crontab.CronExpression.Parser.parse(raw_exp) do
          {:ok, _} -> []
          {:error, message} -> [{field, message}]
        end
      end
    end)
  end

  defp validate_server_access(changeset, user_scope) do
    server_id = get_field(changeset, :server_id)

    cond do
      Keyword.has_key?(changeset.errors, :server_id) ->
        changeset

      is_nil(server_id) ->
        changeset

      true ->
        user_id = user_scope.user.id

        query =
          from s in Server,
            left_join: tu in TeamUser,
            on: tu.team_id == s.team_id,
            where: s.id == ^server_id and (s.user_id == ^user_id or tu.user_id == ^user_id)

        if QueryCanary.Repo.exists?(query) do
          changeset
        else
          add_error(changeset, :server_id, "is not accessible to the current user")
        end
    end
  end

  defp validate_server_id_unchanged(%Ecto.Changeset{data: %__MODULE__{id: nil}} = changeset) do
    changeset
  end

  defp validate_server_id_unchanged(changeset) do
    case get_change(changeset, :server_id) do
      nil -> changeset
      server_id when server_id == changeset.data.server_id -> changeset
      _server_id -> add_error(changeset, :server_id, "cannot be changed after creation")
    end
  end

  defp put_user_id_on_insert(%Ecto.Changeset{data: %__MODULE__{id: nil}} = changeset, user_scope) do
    put_change(changeset, :user_id, user_scope.user.id)
  end

  defp put_user_id_on_insert(changeset, _user_scope), do: changeset
end
