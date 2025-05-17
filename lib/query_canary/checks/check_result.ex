defmodule QueryCanary.Checks.CheckResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "check_results" do
    field :success, :boolean, default: false
    field :error, :string
    field :result, {:array, :map}
    field :time_taken, :integer

    belongs_to :check, QueryCanary.Checks.Check

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(check_result, attrs) do
    check_result
    |> cast(attrs, [:success, :error, :result, :time_taken, :check_id])
    |> validate_required([:success, :result, :time_taken, :check_id])
    |> foreign_key_constraint(:check_id)
  end
end
