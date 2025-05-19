defmodule QueryCanary.Servers do
  @moduledoc """
  The Servers context.
  """

  import Ecto.Query, warn: false
  alias QueryCanary.Repo

  alias QueryCanary.Servers.Server
  alias QueryCanary.Accounts.Scope

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
  Returns the list of servers.

  ## Examples

      iex> list_servers(scope)
      [%Server{}, ...]

  """
  def list_servers(%Scope{} = scope) do
    Repo.all(
      from server in Server,
        where: server.user_id == ^scope.user.id,
        order_by: server.inserted_at
    )
  end

  @doc """
  Gets a single server.

  Raises `Ecto.NoResultsError` if the Server does not exist.

  ## Examples

      iex> get_server!(123)
      %Server{}

      iex> get_server!(456)
      ** (Ecto.NoResultsError)

  """
  def get_server!(%Scope{} = scope, id) do
    Repo.get_by!(Server, id: id, user_id: scope.user.id)
  end

  def get_server(%Scope{} = scope, id) do
    Repo.get_by(Server, id: id, user_id: scope.user.id)
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
    true = server.user_id == scope.user.id

    with {:ok, server = %Server{}} <-
           server
           |> Server.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, server})
      {:ok, server}
    end
  end

  @doc """
  Deletes a server.

  ## Examples

      iex> delete_server(server)
      {:ok, %Server{}}

      iex> delete_server(server)
      {:error, %Ecto.Changeset{}}

  """
  def delete_server(%Scope{} = scope, %Server{} = server) do
    true = server.user_id == scope.user.id

    with {:ok, server = %Server{}} <-
           Repo.delete(server) do
      broadcast(scope, {:deleted, server})
      {:ok, server}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking server changes.

  ## Examples

      iex> change_server(server)
      %Ecto.Changeset{data: %Server{}}

  """
  def change_server(%Scope{} = scope, %Server{} = server, attrs \\ %{}) do
    true = server.user_id == scope.user.id

    Server.changeset(server, attrs, scope)
  end

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
end
