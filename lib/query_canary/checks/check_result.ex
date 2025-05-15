defmodule QueryCanary.Checks.CheckResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "check_results" do
    field :success, :boolean, default: false
    field :result, :string
    field :time_taken, :integer
    field :check_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(checks, attrs, user_scope) do
    checks
    |> cast(attrs, [:success, :result, :time_taken])
    |> validate_required([:success, :result, :time_taken])
    |> put_change(:user_id, user_scope.user.id)
  end
end
