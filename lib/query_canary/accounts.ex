defmodule QueryCanary.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias QueryCanary.Repo

  alias QueryCanary.Accounts.{User, UserToken, UserNotifier, Team, TeamUser, Scope}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `QueryCanary.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset = User.email_changeset(user, %{email: email})

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `QueryCanary.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, %User{}, [...]}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
    |> case do
      {:ok, user, expired_tokens} -> {:ok, user, expired_tokens}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, user, []}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc ~S"""
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  def deliver_invite_instructions(%User{} = user, %Team{} = team, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    UserNotifier.deliver_invite_instructions(user, team, magic_link_url_fun.(team.id))
  end

  def deliver_invite_register_instructions(%User{} = user, %Team{} = team, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")

    Repo.insert!(user_token)

    UserNotifier.deliver_invite_register_instructions(
      user,
      team,
      magic_link_url_fun.(encoded_token)
    )
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    %{data: %User{} = user} = changeset

    with {:ok, %{user: user, tokens_to_expire: expired_tokens}} <-
           Ecto.Multi.new()
           |> Ecto.Multi.update(:user, changeset)
           |> Ecto.Multi.all(:tokens_to_expire, UserToken.by_user_and_contexts_query(user, :all))
           |> Ecto.Multi.delete_all(:tokens, fn %{tokens_to_expire: tokens_to_expire} ->
             UserToken.delete_all_query(tokens_to_expire)
           end)
           |> Repo.transaction() do
      {:ok, user, expired_tokens}
    end
  end

  ## Teams Logic

  @doc """
  Returns the list of teams the user is associated with.

  ## Examples

      iex> list_teams(scope)
      [%Team{}, ...]

  """
  def list_teams(%Scope{} = scope) do
    Repo.all(
      from t in Team,
        join: tu in TeamUser,
        on: tu.team_id == t.id,
        where: tu.user_id == ^scope.user.id,
        preload: [:team_users]
    )
  end

  @doc """
  Gets a single team the user is associated with.

  Raises `Ecto.NoResultsError` if the Team does not exist or the user is not associated with it.

  ## Examples

      iex> get_team!(scope, 123)
      %Team{}

      iex> get_team!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_team!(%Scope{} = scope, id) do
    Repo.one!(
      from t in Team,
        join: tu in TeamUser,
        on: tu.team_id == t.id,
        where: tu.user_id == ^scope.user.id and t.id == ^id,
        preload: [:team_users]
    )
  end

  @doc """
  Creates a team and associates the user as an admin.

  ## Examples

      iex> create_team(scope, %{field: value})
      {:ok, %Team{}}

      iex> create_team(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_team(%Scope{} = scope, attrs) do
    Repo.transaction(fn ->
      with {:ok, team} <-
             %Team{}
             |> Team.changeset(attrs, scope)
             |> Repo.insert(),
           {:ok, _team_user} <-
             %TeamUser{}
             |> TeamUser.changeset(%{team_id: team.id, user_id: scope.user.id, role: :admin})
             |> Repo.insert() do
        broadcast(scope, {:created, team})
        {:ok, team}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> then(fn x ->
      # unwrap
      case x do
        {:ok, resp} -> resp
        x -> x
      end
    end)
  end

  @doc """
  Updates a team if the user is associated with it.

  ## Examples

      iex> update_team(scope, team, %{field: new_value})
      {:ok, %Team{}}

      iex> update_team(scope, team, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_team(%Scope{} = scope, %Team{} = team, attrs) do
    true = user_has_access_to_team?(scope.user.id, team.id)

    with {:ok, team} <-
           team
           |> Team.changeset(attrs, scope)
           |> Repo.update() do
      broadcast(scope, {:updated, team})
      {:ok, team}
    end
  end

  def update_team_billing(%Scope{} = scope, %Team{} = team, attrs) do
    true = user_has_access_to_team?(scope.user.id, team.id)

    with {:ok, team} <-
           team
           |> Team.stripe_changeset(attrs)
           |> Repo.update() do
      broadcast(scope, {:updated, team})
      {:ok, team}
    end
  end

  @doc """
  Deletes a team if the user is associated with it.

  ## Examples

      iex> delete_team(scope, team)
      {:ok, %Team{}}

      iex> delete_team(scope, team)
      {:error, %Ecto.Changeset{}}

  """
  def delete_team(%Scope{} = scope, %Team{} = team) do
    true = user_has_access_to_team?(scope.user.id, team.id, :admin)

    with {:ok, team} <- Repo.delete(team) do
      broadcast(scope, {:deleted, team})
      {:ok, team}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking team changes.

  ## Examples

      iex> change_team(scope, team)
      %Ecto.Changeset{data: %Team{}}

  """
  def change_team(%Scope{} = scope, %Team{} = team, attrs \\ %{}) do
    true = user_has_access_to_team?(scope.user.id, team.id, :admin)

    Team.changeset(team, attrs, scope)
  end

  ## Helper Functions
  def user_has_access_to_team?(user_id, team_id, role \\ nil)

  # def user_has_access_to_team?(_user_id, nil, _) do
  #   true
  # end

  # def user_has_access_to_team?(_user_id, nil, _role) do
  #   false
  # end

  def user_has_access_to_team?(_user_id, nil, _role) do
    true
  end

  def user_has_access_to_team?(user_id, team_id, nil) do
    Repo.exists?(
      from tu in TeamUser,
        where: tu.user_id == ^user_id and tu.team_id == ^team_id
    )
  end

  def user_has_access_to_team?(user_id, team_id, role) do
    Repo.exists?(
      from tu in TeamUser,
        where: tu.user_id == ^user_id and tu.team_id == ^team_id and tu.role == ^role
    )
  end

  @doc """
  Subscribes to scoped notifications about any team changes.

  The broadcasted messages match the pattern:

    * {:created, %Team{}}
    * {:updated, %Team{}}
    * {:deleted, %Team{}}

  """
  def subscribe_teams(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(QueryCanary.PubSub, "user:#{key}:teams")
  end

  defp broadcast(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(QueryCanary.PubSub, "user:#{key}:teams", message)
  end

  @doc """
  Invites a user to a team by email.

  If the user does not exist, they will be created and associated with the team.

  ## Examples

      iex> invite_user_to_team(team, "user@example.com")
      {:ok, %User{}}

      iex> invite_user_to_team(team, "invalid-email")
      {:error, "Invalid email"}

  """
  def invite_user_to_team(%Scope{} = _scope, %Team{} = team, email) when is_binary(email) do
    Repo.transaction(fn ->
      case get_user_by_email(email) do
        nil ->
          # Create a new user if they don't exist
          {:ok, user} = register_user(%{email: email})
          associate_user_with_team(team, user)
          user

        %User{} = user ->
          # Associate the existing user with the team
          associate_user_with_team(team, user)
          user
      end
    end)
  end

  @doc """
  Lists all users associated with a team.

  ## Examples

      iex> list_team_users(team)
      [%User{}, ...]

  """
  def list_team_users(%Scope{} = _scope, %Team{} = team) do
    Repo.all(
      from u in User,
        join: tu in TeamUser,
        on: tu.user_id == u.id,
        where: tu.team_id == ^team.id,
        select: {u, tu.role}
    )
  end

  @doc """
  Removes a user from a team.

  ## Examples

      iex> remove_user_from_team(team, user_id)
      {:ok, %TeamUser{}}

      iex> remove_user_from_team(team, invalid_user_id)
      {:error, "User not found in team"}

  """
  def remove_user_from_team(%Scope{} = scope, %Team{} = team, user_id) do
    true = user_has_access_to_team?(scope.user.id, team.id, :admin)

    case Repo.get_by(TeamUser, team_id: team.id, user_id: user_id) do
      nil ->
        {:error, "User not found in team"}

      %TeamUser{} = team_user ->
        Repo.delete(team_user)
    end
  end

  def accept_team_invite(%Scope{} = scope, %Team{} = team) do
    Repo.get_by(TeamUser, team_id: team.id, user_id: scope.user.id)
    |> TeamUser.changeset(%{role: :member})
    |> Repo.update()
  end

  def accept_pending_team_invites(%User{} = user) do
    from(tu in TeamUser,
      where: tu.user_id == ^user.id and tu.role == :invited,
      update: [set: [role: :member]]
    )
    |> QueryCanary.Repo.update_all([])
  end

  ## Helper Functions

  defp associate_user_with_team(%Team{} = team, %User{} = user) do
    %TeamUser{}
    |> TeamUser.changeset(%{team_id: team.id, user_id: user.id, role: :invited})
    |> Repo.insert()
  end
end
