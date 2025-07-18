defmodule QueryCanary.Servers.Server do
  use Ecto.Schema
  import Ecto.Changeset

  schema "servers" do
    field :name, :string

    field :db_engine, :string
    field :db_hostname, :string
    field :db_port, :integer
    field :db_name, :string
    field :db_username, :string
    field :db_password, :string, redact: true
    field :db_password_input, :string, virtual: true
    field :db_ssl_mode, :string, default: "allow"
    field :db_ssl_cert, :string, redact: true
    field :db_ssl_key, :string, redact: true
    field :db_ssl_ca_cert, :string, redact: true

    field :ssh_tunnel, :boolean
    field :ssh_hostname, :string
    field :ssh_username, :string
    field :ssh_port, :integer
    field :ssh_public_key, :string
    field :ssh_private_key, :string, redact: true
    field :ssh_key_type, :string
    field :ssh_key_generated_at, :utc_datetime

    field :schema, :map, default: %{}

    belongs_to :user, QueryCanary.Accounts.User
    belongs_to :team, QueryCanary.Accounts.Team

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(server, attrs, user_scope) do
    server
    |> cast(attrs, [
      :name,
      :db_engine,
      :db_hostname,
      :db_port,
      :db_name,
      :db_username,
      :db_password_input,
      :db_ssl_mode,
      :db_ssl_cert,
      :db_ssl_key,
      :db_ssl_ca_cert,
      :ssh_tunnel,
      :ssh_hostname,
      :ssh_username,
      :ssh_port,
      :ssh_public_key,
      :ssh_private_key,
      :ssh_key_type,
      :ssh_key_generated_at,
      :team_id
    ])
    |> validate_required([
      :name,
      :db_engine,
      :db_hostname,
      :db_port,
      :db_name,
      :db_username
    ])
    |> validate_password_field(:db_password_input, :db_password)
    |> validate_ssh_tunnel_fields()
    |> validate_ownership(user_scope)
    |> transfer_password_fields()
    |> encrypt_sensitive_fields()
  end

  def schema_changeset(server, attrs) do
    server
    |> cast(attrs, [:schema])
  end

  defp validate_password_field(changeset, input_field, target_field) do
    input = get_field(changeset, input_field)
    target = get_field(changeset, target_field)

    # Make sure at least one authentication method is provided
    if is_nil(input) and is_nil(target) do
      add_error(changeset, input_field, "is required")
    else
      changeset
    end
  end

  defp validate_ssh_tunnel_fields(changeset) do
    if get_field(changeset, :ssh_tunnel) do
      # SSH tunnel is enabled, so require SSH hostname, username, and port
      changeset
      |> validate_required([
        :ssh_hostname,
        :ssh_username,
        :ssh_port,
        :ssh_public_key,
        :ssh_private_key,
        :ssh_key_type,
        :ssh_key_generated_at
      ])
    else
      changeset
    end
  end

  import Ecto.Query

  defp validate_ownership(changeset, user_scope) do
    user_id = user_scope.user.id
    team_id = get_field(changeset, :team_id)

    if is_nil(team_id) do
      # Owned by the user
      changeset
      |> put_change(:team_id, nil)
      |> put_change(:user_id, user_id)
    else
      # Owned by the team
      query =
        from tu in QueryCanary.Accounts.TeamUser,
          where: tu.team_id == ^team_id and tu.user_id == ^user_id

      if QueryCanary.Repo.exists?(query) do
        changeset
        |> put_change(:user_id, nil)
      else
        add_error(changeset, :team_id, "does not belong to the current user.")
      end
    end
  end

  defp transfer_password_fields(changeset) do
    changeset
    |> maybe_put_password(:db_password_input, :db_password)
  end

  defp maybe_put_password(changeset, input_field, target_field) do
    case get_change(changeset, input_field) do
      # No input, keep existing value
      nil -> changeset
      # Empty input, keep existing value
      "" -> changeset
      # Transfer input to real field
      value -> put_change(changeset, target_field, value)
    end
  end

  defp encrypt_sensitive_fields(changeset) do
    changeset
    |> update_change(:db_password, &encrypt(&1, "db_password"))
    |> update_change(:ssh_private_key, &maybe_encrypt(&1, "ssh_private_key"))
  end

  defp encrypt(nil, _), do: nil

  defp encrypt(value, salt),
    do: Phoenix.Token.encrypt(QueryCanaryWeb.Endpoint, salt, value)

  defp maybe_encrypt(nil, _), do: nil
  defp maybe_encrypt(value, salt), do: encrypt(value, salt)
end
