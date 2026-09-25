defmodule QueryCanaryWeb.SlackIntegrationController do
  use QueryCanaryWeb, :controller
  alias QueryCanary.Notifications
  alias QueryCanary.Notifications.Slack

  def connect(conn, %{"team_id" => team_id}) do
    cond do
      not Notifications.admin?(conn.assigns.current_scope, team_id) ->
        conn
        |> put_flash(:error, "Only team admins can connect Slack.")
        |> redirect(to: ~p"/teams")

      not Slack.configured?() ->
        conn
        |> put_flash(:error, "Slack has not been configured for this installation.")
        |> redirect(to: ~p"/teams/#{team_id}")

      true ->
        state =
          Phoenix.Token.sign(QueryCanaryWeb.Endpoint, "slack oauth", %{
            team_id: team_id,
            user_id: conn.assigns.current_scope.user.id,
            nonce: Base.url_encode64(:crypto.strong_rand_bytes(32))
          })

        conn
        |> put_session(:slack_oauth_state, state)
        |> redirect(external: Slack.authorize_url(state))
    end
  end

  def callback(conn, params) do
    saved_state = get_session(conn, :slack_oauth_state)
    conn = delete_session(conn, :slack_oauth_state)

    with state when is_binary(state) <- params["state"],
         true <- is_binary(saved_state) and Plug.Crypto.secure_compare(saved_state, state),
         {:ok, %{team_id: team_id, user_id: user_id}} <-
           Phoenix.Token.verify(QueryCanaryWeb.Endpoint, "slack oauth", state, max_age: 600),
         true <- user_id == conn.assigns.current_scope.user.id,
         true <- Notifications.admin?(conn.assigns.current_scope, team_id) do
      finish_connection(conn, params, team_id)
    else
      _ ->
        conn
        |> put_flash(:error, "Slack connection expired or was invalid. Please try again.")
        |> redirect(to: ~p"/teams")
    end
  end

  defp finish_connection(conn, %{"code" => code}, team_id) when is_binary(code) do
    with {:ok, installation} <- Slack.exchange_code(code),
         {:ok, _} <-
           Notifications.connect_slack(conn.assigns.current_scope, team_id, installation) do
      conn
      |> put_flash(:info, "Slack connected. Choose a channel in each check's settings.")
      |> redirect(to: ~p"/teams/#{team_id}")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not connect Slack. Please try again.")
        |> redirect(to: ~p"/teams/#{team_id}")
    end
  end

  defp finish_connection(conn, _, team_id) do
    conn
    |> put_flash(:error, "Slack connection was cancelled.")
    |> redirect(to: ~p"/teams/#{team_id}")
  end
end
