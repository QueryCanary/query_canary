defmodule QueryCanary.Notifications.Destination do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_destinations" do
    field :channel_id, :string
    belongs_to :check, QueryCanary.Checks.Check
    belongs_to :integration, QueryCanary.Notifications.Integration
    timestamps(type: :utc_datetime)
  end

  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [:check_id, :integration_id, :channel_id])
    |> validate_required([:check_id, :integration_id, :channel_id])
    |> unique_constraint([:check_id, :integration_id])
    |> foreign_key_constraint(:check_id)
    |> foreign_key_constraint(:integration_id)
  end
end
