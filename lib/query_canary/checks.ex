defmodule QueryCanary.Checks do
  @moduledoc """
  The Checks context.
  """

  import Ecto.Query, warn: false
  alias QueryCanary.Repo

  alias QueryCanary.Checks.Check
  alias QueryCanary.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any check changes.

  The broadcasted messages match the pattern:

    * {:created, %Check{}}
    * {:updated, %Check{}}
    * {:deleted, %Check{}}

  """
  def subscribe_checks(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(QueryCanary.PubSub, "user:#{key}:checks")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(QueryCanary.PubSub, "user:#{key}:checks", message)
  end

  @doc """
  Returns the list of checks.

  ## Examples

      iex> list_checks(scope)
      [%Check{}, ...]

  """
  def list_checks(%Scope{} = scope) do
    Repo.all(from check in Check, where: check.user_id == ^scope.user.id)
  end

  @doc """
  Gets a single check.

  Raises `Ecto.NoResultsError` if the Check does not exist.

  ## Examples

      iex> get_check!(123)
      %Check{}

      iex> get_check!(456)
      ** (Ecto.NoResultsError)

  """
  def get_check!(%Scope{} = scope, id) do
    Repo.get_by!(Check, id: id, user_id: scope.user.id)
    |> Repo.preload(:server)
  end

  @doc """
  Creates a check.

  ## Examples

      iex> create_check(%{field: value})
      {:ok, %Check{}}

      iex> create_check(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_check(%Scope{} = scope, attrs) do
    with {:ok, check = %Check{}} <-
           %Check{}
           |> Check.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast(scope, {:created, check})
      {:ok, check}
    end
  end

  @doc """
  Updates a check.

  ## Examples

      iex> update_check(check, %{field: new_value})
      {:ok, %Check{}}

      iex> update_check(check, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_check(%Scope{} = scope, %Check{} = check, attrs) do
    true = check.user_id == scope.user.id

    with {:ok, check = %Check{}} <-
           check
           |> Check.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, check})
      {:ok, check}
    end
  end

  @doc """
  Deletes a check.

  ## Examples

      iex> delete_check(check)
      {:ok, %Check{}}

      iex> delete_check(check)
      {:error, %Ecto.Changeset{}}

  """
  def delete_check(%Scope{} = scope, %Check{} = check) do
    true = check.user_id == scope.user.id

    with {:ok, check = %Check{}} <-
           Repo.delete(check) do
      broadcast(scope, {:deleted, check})
      {:ok, check}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking check changes.

  ## Examples

      iex> change_check(check)
      %Ecto.Changeset{data: %Check{}}

  """
  def change_check(%Scope{} = scope, %Check{} = check, attrs \\ %{}) do
    true = check.user_id == scope.user.id

    Check.changeset(check, attrs, scope)
  end

  def list_checks_by_server(%Scope{} = scope, server_id) do
    Repo.all(
      from c in Check,
        where: c.user_id == ^scope.user.id and c.server_id == ^server_id,
        order_by: [desc: c.updated_at]
    )
  end
end
