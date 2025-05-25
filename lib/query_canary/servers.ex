defmodule QueryCanary.Servers do
  @moduledoc """
  The Servers context.
  """

  import Ecto.Query, warn: false
  alias QueryCanary.Repo

  alias QueryCanary.Servers.Server
  alias QueryCanary.Accounts.{Scope, TeamUser}

  @doc """
  Subscribes to scoped notifications about any server changes.

  The broadcasted messages match the pattern:

    * {:created, %Server{}}
    * {:updated, %Server{}}
    * {:deleted, %Server{}}

  """
  def subscribe_servers(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(QueryCanary.PubSub, "user:#{key}:servers")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(QueryCanary.PubSub, "user:#{key}:servers", message)
  end

  @doc """
  Returns the list of servers accessible to the user.

  Includes servers owned by the user and servers owned by teams the user is a member of.

  ## Examples

      iex> list_servers(scope)
      [%Server{}, ...]

  """
  def list_servers(%Scope{} = scope) do
    Server
    |> accessible_by_user(scope.user.id)
    |> order_by([s], s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single server accessible to the user.

  Includes servers owned by the user and servers owned by teams the user is a member of.

  Raises `Ecto.NoResultsError` if the Server does not exist or is not accessible.

  ## Examples

      iex> get_server!(scope, 123)
      %Server{}

      iex> get_server!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_server!(%Scope{} = scope, id) do
    Server
    |> where([s], s.id == ^id)
    |> accessible_by_user(scope.user.id)
    |> Repo.one!()
  end

  def get_server(%Scope{} = scope, id) do
    Server
    |> where([s], s.id == ^id)
    |> accessible_by_user(scope.user.id)
    |> Repo.one()
  end

  @doc """
  Creates a server.

  ## Examples

      iex> create_server(%{field: value})
      {:ok, %Server{}}

      iex> create_server(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_server(%Scope{} = scope, attrs) do
    with {:ok, server = %Server{}} <-
           %Server{}
           |> Server.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast(scope, {:created, server})
      {:ok, server}
    end
  end

  @doc """
  Updates a server.

  ## Examples

      iex> update_server(server, %{field: new_value})
      {:ok, %Server{}}

      iex> update_server(server, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_server(%Scope{} = scope, %Server{} = server, attrs) do
    ensure_access!(server, scope.user.id)

    with {:ok, server = %Server{}} <-
           server
           |> Server.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, server})
      {:ok, server}
    end
  end

  @doc """
  Deletes a server if the user has access to it.

  ## Examples

      iex> delete_server(scope, server)
      {:ok, %Server{}}

      iex> delete_server(scope, server)
      {:error, %Ecto.Changeset{}}

  """
  def delete_server(%Scope{} = scope, %Server{} = server) do
    ensure_access!(server, scope.user.id)

    with {:ok, server = %Server{}} <- Repo.delete(server) do
      broadcast(scope, {:deleted, server})
      {:ok, server}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking server changes.

  ## Examples

      iex> change_server(scope, server)
      %Ecto.Changeset{data: %Server{}}

  """
  def change_server(%Scope{} = scope, %Server{} = server, attrs \\ %{}) do
    ensure_access!(server, scope.user.id)

    Server.changeset(server, attrs, scope)
  end

  @doc """
  Updates the introspection schema for a server.

  ## Examples

      iex> update_introspection(server)
      {:ok, %Server{}}

      iex> update_introspection(server)
      {:error, reason}

  """
  def update_introspection(%Server{} = server) do
    with {:ok, schema} <- QueryCanary.Connections.SQLSchemaProvider.get_codemirror_schema(server),
         changeset <- Server.schema_changeset(server, %{schema: schema}),
         {:ok, %Server{} = server} <- Repo.update(changeset) do
      {:ok, server}
    else
      error ->
        error
    end
  end

  ## Helper Functions
  def accessible_by_user(query, user_id) do
    query
    |> join(:left, [s], tu in TeamUser, on: tu.team_id == s.team_id)
    |> where([s, tu], tu.user_id == ^user_id or s.user_id == ^user_id)
  end

  defp ensure_access!(%Server{} = server, user_id) do
    cond do
      not is_nil(server.user_id) and server.user_id == user_id ->
        true

      not is_nil(server.team_id) and
          QueryCanary.Accounts.user_has_access_to_team?(user_id, server.team_id) ->
        true

      true ->
        raise AccessError, message: "Server not accessible to the user"
    end
  end
end

defmodule AccessError do
  defexception message: "no permission to access"
end
