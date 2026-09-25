defmodule QueryCanary.Notifications do
  @moduledoc "Team-owned chat connections and per-check notification destinations."
  import Ecto.Query
  import Ecto.Changeset
  alias QueryCanary.{Repo, Accounts}
  alias QueryCanary.Accounts.{Scope, Team, TeamUser}
  alias QueryCanary.Notifications.{Integration, Destination, Slack}
  alias QueryCanary.Servers.Server

  def providers, do: %{"slack" => Slack}

  def enabled?(check, provider), do: Map.get(check.notification_preferences, provider, true)

  def validate_preferences_access(changeset, scope) do
    if get_change(changeset, :notification_preferences) do
      server_id = get_field(changeset, :server_id)
      server = if server_id, do: Repo.get(Server, server_id)

      if server && server.team_id && not member?(scope, server.team_id) do
        add_error(
          changeset,
          :notification_preferences,
          "only active members can configure team alerts"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  def member?(%Scope{user: user}, team_id) when not is_nil(team_id) do
    Repo.exists?(
      from tu in TeamUser,
        where: tu.user_id == ^user.id and tu.team_id == ^team_id and tu.role in [:admin, :member]
    )
  end

  def member?(_, _), do: false

  def admin?(%Scope{user: user}, team_id) when not is_nil(team_id),
    do: Accounts.user_has_access_to_team?(user.id, team_id, :admin)

  def admin?(_, _), do: false

  # Only non-secret connection metadata is returned to LiveViews.
  def list_integrations(scope, team_id) do
    if member?(scope, team_id) do
      Repo.all(
        from i in Integration,
          where: i.team_id == ^team_id,
          select: map(i, [:id, :team_id, :provider, :external_id, :name])
      )
    else
      []
    end
  end

  def connect_slack(scope, team_id, installation) do
    if admin?(scope, team_id) do
      Repo.transaction(fn ->
        # Serialize connection replacement and enforce one provider connection per team.
        Repo.one!(from t in Team, where: t.id == ^team_id, lock: "FOR UPDATE")
        existing = Repo.get_by(Integration, team_id: team_id, provider: "slack")

        # A different workspace must never inherit the previous workspace's channels or jobs.
        integration =
          if existing && existing.external_id != installation.external_id do
            Repo.delete!(existing)
            %Integration{}
          else
            existing || %Integration{}
          end

        integration
        |> Integration.changeset(%{
          team_id: team_id,
          provider: "slack",
          external_id: installation.external_id,
          name: installation.name,
          encrypted_token: Integration.encrypt_token(installation.token)
        })
        |> Repo.insert_or_update!()
      end)
    else
      {:error, :forbidden}
    end
  end

  def disconnect(scope, team_id, provider) do
    if admin?(scope, team_id) do
      Repo.transaction(fn ->
        Repo.one!(from t in Team, where: t.id == ^team_id, lock: "FOR UPDATE")

        Repo.delete_all(
          from i in Integration, where: i.team_id == ^team_id and i.provider == ^provider
        )
      end)
    else
      {:error, :forbidden}
    end
  end

  def list_channels(scope, team_id, provider) do
    with true <- member?(scope, team_id),
         %Integration{} = integration <-
           Repo.get_by(Integration, team_id: team_id, provider: provider),
         {:ok, adapter} <- Map.fetch(providers(), provider),
         {:ok, token} <- Integration.token(integration) do
      adapter.list_channels(token)
    else
      _ -> {:error, :not_connected}
    end
  end

  def channels_for_check(%{id: nil}), do: %{}

  def channels_for_check(check) do
    Repo.all(
      from d in Destination,
        join: i in Integration,
        on: i.id == d.integration_id,
        join: s in Server,
        on: s.team_id == i.team_id,
        where: d.check_id == ^check.id and s.id == ^check.server_id,
        select: {i.provider, d.channel_id}
    )
    |> Map.new()
  end

  def validate_channels(changeset, scope) do
    case get_change(changeset, :notification_channels) do
      nil ->
        changeset

      channels ->
        server_id = get_field(changeset, :server_id)
        server = if server_id, do: Repo.get(Server, server_id)
        team_id = server && server.team_id
        can_manage = member?(scope, team_id)
        integrations = list_integrations(scope, team_id)

        Enum.reduce(channels, changeset, fn {provider, channel_id}, cs ->
          cond do
            not Map.has_key?(providers(), provider) ->
              add_error(cs, :notification_channels, "contains an unsupported provider")

            not can_manage ->
              add_error(
                cs,
                :notification_channels,
                "only active members can configure team alerts"
              )

            channel_id in [nil, ""] ->
              cs

            not Enum.any?(integrations, &(&1.provider == provider)) ->
              add_error(
                cs,
                :notification_channels,
                "connect #{provider} to this check's team first"
              )

            not providers()[provider].valid_channel_id?(channel_id) ->
              add_error(cs, :notification_channels, "select a valid #{provider} channel")

            true ->
              cs
          end
        end)
    end
  end

  @doc "Saves a check and its destinations atomically. Only explicitly supplied providers are changed."
  def save_check(%Ecto.Changeset{valid?: false} = changeset, _scope), do: {:error, changeset}

  def save_check(changeset, scope) do
    Repo.transaction(fn ->
      server_id = get_field(changeset, :server_id)
      server = if server_id, do: Repo.get(Server, server_id)
      team_id = server && server.team_id

      if team_id do
        Repo.one!(from t in Team, where: t.id == ^team_id, lock: "FOR UPDATE")
      end

      changeset = changeset |> validate_channels(scope) |> validate_preferences_access(scope)

      case Repo.insert_or_update(changeset) do
        {:ok, check} ->
          for {provider, channel_id} <- get_change(changeset, :notification_channels) || %{} do
            if team_id do
              integration = Repo.get_by(Integration, team_id: team_id, provider: provider)

              if integration do
                destination =
                  Repo.get_by(Destination, check_id: check.id, integration_id: integration.id)

                cond do
                  channel_id in [nil, ""] ->
                    if destination, do: Repo.delete!(destination)

                  destination && destination.channel_id == channel_id ->
                    :ok

                  true ->
                    # Replace rather than update, so pending jobs for the old channel are cancelled.
                    if destination, do: Repo.delete!(destination)

                    %Destination{}
                    |> Destination.changeset(%{
                      check_id: check.id,
                      integration_id: integration.id,
                      channel_id: channel_id
                    })
                    |> Repo.insert!()
                end
              end
            end
          end

          check

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def enqueue_alert(check, result) do
    if result.is_alert and result.check_id == check.id do
      # Reread preferences so a running check cannot use settings from before it was muted.
      check = Repo.get!(QueryCanary.Checks.Check, check.id)

      destinations =
        Repo.all(
          from d in Destination,
            join: i in Integration,
            on: i.id == d.integration_id,
            join: s in Server,
            on: s.team_id == i.team_id,
            where: d.check_id == ^check.id and s.id == ^check.server_id
        )
        |> Repo.preload(:integration)
        |> Enum.filter(&enabled?(check, &1.integration.provider))

      Repo.transaction(fn ->
        Enum.map(destinations, fn destination ->
          %{destination_id: destination.id, check_result_id: result.id}
          |> QueryCanary.Jobs.DeliverNotification.new()
          |> Oban.insert!()
        end)
      end)
    else
      {:ok, :no_alert}
    end
  end
end
