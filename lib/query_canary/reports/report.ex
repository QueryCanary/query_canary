defmodule QueryCanary.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias QueryCanary.Accounts.Scope
  alias QueryCanary.Accounts.TeamUser

  schema "reports" do
    field :name, :string
    field :description, :string
    field :timezone, :string, default: "Etc/UTC"
    field :default_range, :string, default: "today"
    field :settings, :map, default: %{}

    belongs_to :user, QueryCanary.Accounts.User
    belongs_to :team, QueryCanary.Accounts.Team

    has_many :groups, QueryCanary.Reports.ReportGroup

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name timezone default_range)a
  @optional_fields ~w(description settings team_id user_id)a

  @doc """
  Changeset that infers ownership from the provided scope. Behaviour matches servers/checks.
  """
  def changeset(report, attrs, %Scope{} = scope) do
    report
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> maybe_put_owner(scope, attrs)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2)
    |> validate_timezone()
    |> put_default_settings()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2)
    |> validate_timezone()
    |> put_default_settings()
  end

  defp maybe_put_owner(changeset, %Scope{} = scope, attrs) do
    has_team_param? = Map.has_key?(attrs, "team_id") or Map.has_key?(attrs, :team_id)

    cond do
      has_team_param? ->
        case Map.get(attrs, "team_id") || Map.get(attrs, :team_id) do
          nil ->
            changeset
            |> put_change(:user_id, scope.user.id)
            |> put_change(:team_id, nil)

          team_id ->
            team_id = normalize_team_id(team_id)

            if valid_team_membership?(scope.user.id, team_id) do
              changeset
              |> put_change(:team_id, team_id)
              |> put_change(:user_id, nil)
            else
              add_error(changeset, :team_id, "is not accessible to the current user")
            end
        end

      is_nil(changeset.data.id) ->
        changeset
        |> put_change(:user_id, scope.user.id)
        |> put_change(:team_id, nil)

      true ->
        changeset
    end
  end

  defp valid_team_membership?(user_id, team_id) do
    QueryCanary.Repo.exists?(
      from tu in TeamUser,
        where: tu.team_id == ^team_id and tu.user_id == ^user_id and tu.role != :invited
    )
  end

  defp validate_timezone(changeset) do
    case get_field(changeset, :timezone) do
      tz when is_binary(tz) ->
        case DateTime.now(tz, Calendar.get_time_zone_database()) do
          {:ok, _dt} -> changeset
          {:error, _} -> add_error(changeset, :timezone, "is not a valid IANA timezone")
        end

      _ ->
        changeset
    end
  end

  defp put_default_settings(changeset) do
    update_change(changeset, :settings, fn
      nil -> %{}
      settings -> settings
    end)
  end

  defp normalize_team_id(team_id) when is_binary(team_id) do
    case Integer.parse(team_id) do
      {int, ""} -> int
      _ -> team_id
    end
  end

  defp normalize_team_id(team_id), do: team_id
end
