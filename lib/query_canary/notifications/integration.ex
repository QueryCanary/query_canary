defmodule QueryCanary.Notifications.Integration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_integrations" do
    field :provider, :string
    field :external_id, :string
    field :name, :string
    field :encrypted_token, :string, redact: true
    belongs_to :team, QueryCanary.Accounts.Team
    timestamps(type: :utc_datetime)
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:team_id, :provider, :external_id, :name, :encrypted_token])
    |> validate_required([:team_id, :provider, :external_id, :name, :encrypted_token])
    |> unique_constraint([:team_id, :provider])
    |> foreign_key_constraint(:team_id)
  end

  def encrypt_token(token) do
    Phoenix.Token.encrypt(QueryCanaryWeb.Endpoint, "notification credentials", token)
  end

  def token(integration) do
    Phoenix.Token.decrypt(
      QueryCanaryWeb.Endpoint,
      "notification credentials",
      integration.encrypted_token,
      max_age: :infinity
    )
  end
end
