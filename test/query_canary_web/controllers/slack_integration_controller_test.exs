defmodule QueryCanaryWeb.SlackIntegrationControllerTest do
  use QueryCanaryWeb.ConnCase
  import QueryCanary.AccountsFixtures
  alias QueryCanary.{Accounts, Notifications, Repo}
  alias QueryCanary.Notifications.{Slack, Integration}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    previous = Application.get_env(:query_canary, :slack)

    Application.put_env(:query_canary, :slack,
      client_id: "client-id",
      client_secret: "client-secret"
    )

    on_exit(fn -> Application.put_env(:query_canary, :slack, previous) end)
    %{team: team_fixture(scope)}
  end

  test "admin connects through OAuth with session-bound state and encrypted bot token", ctx do
    conn = post(ctx.conn, ~p"/teams/#{ctx.team}/integrations/slack")
    uri = URI.parse(redirected_to(conn))
    assert uri.host == "slack.com"
    params = URI.decode_query(uri.query)
    assert params["scope"] == "chat:write,channels:read,groups:read,files:write"

    assert params["redirect_uri"] ==
             QueryCanaryWeb.Endpoint.url() <> "/integrations/slack/callback"

    assert get_session(conn, :slack_oauth_state) == params["state"]

    Req.Test.expect(Slack, fn request ->
      assert request.request_path == "/api/oauth.v2.access"
      {:ok, body, request} = read_body(request)
      form = URI.decode_query(body)
      assert form["code"] == "authorization-code"
      assert form["client_secret"] == "client-secret"
      assert form["redirect_uri"] == params["redirect_uri"]

      Req.Test.json(request, %{
        ok: true,
        token_type: "bot",
        access_token: "xoxb-secret",
        scope: "chat:write,channels:read,groups:read,files:write",
        team: %{id: "T12345678", name: "Workspace"}
      })
    end)

    conn =
      get(conn, ~p"/integrations/slack/callback", %{
        state: params["state"],
        code: "authorization-code"
      })

    assert redirected_to(conn) == ~p"/teams/#{ctx.team}"
    assert get_session(conn, :slack_oauth_state) == nil
    integration = Repo.get_by!(Integration, team_id: ctx.team.id)
    assert {:ok, "xoxb-secret"} = Integration.token(integration)
    assert integration.name == "Workspace"
    refute integration.encrypted_token =~ "xoxb-secret"

    replay =
      get(conn, ~p"/integrations/slack/callback", %{
        state: params["state"],
        code: "authorization-code"
      })

    assert redirected_to(replay) == ~p"/teams"
  end

  test "invalid, missing, expired and cross-user state cannot connect", ctx do
    for params <- [%{code: "x"}, %{state: "forged", code: "x"}] do
      conn = get(ctx.conn, ~p"/integrations/slack/callback", params)
      assert redirected_to(conn) == ~p"/teams"
    end

    for {user_id, signed_at} <- [
          {ctx.scope.user.id, System.system_time(:second) - 601},
          {ctx.scope.user.id + 1, System.system_time(:second)}
        ] do
      state =
        Phoenix.Token.sign(
          QueryCanaryWeb.Endpoint,
          "slack oauth",
          %{team_id: ctx.team.id, user_id: user_id},
          signed_at: signed_at
        )

      conn =
        ctx.conn
        |> put_session(:slack_oauth_state, state)
        |> get(~p"/integrations/slack/callback", %{state: state, code: "x"})

      assert redirected_to(conn) == ~p"/teams"
    end

    assert Repo.all(Integration) == []
  end

  test "cancellation clears state without connecting", ctx do
    conn = post(ctx.conn, ~p"/teams/#{ctx.team}/integrations/slack")
    state = get_session(conn, :slack_oauth_state)
    conn = get(conn, ~p"/integrations/slack/callback", %{state: state, error: "access_denied"})
    assert redirected_to(conn) == ~p"/teams/#{ctx.team}"
    assert get_session(conn, :slack_oauth_state) == nil
    assert Repo.all(Integration) == []
  end

  test "non-admins cannot start OAuth and losing admin access invalidates callback", ctx do
    member = user_scope_fixture()
    {:ok, _} = Accounts.invite_user_to_team(ctx.scope, ctx.team, member.user.email)
    {:ok, _} = Accounts.accept_team_invite(member, ctx.team)

    conn =
      build_conn() |> log_in_user(member.user) |> post(~p"/teams/#{ctx.team}/integrations/slack")

    assert redirected_to(conn) == ~p"/teams"

    conn = post(ctx.conn, ~p"/teams/#{ctx.team}/integrations/slack")
    state = get_session(conn, :slack_oauth_state)

    Repo.get_by!(Accounts.TeamUser, team_id: ctx.team.id, user_id: ctx.scope.user.id)
    |> Ecto.Changeset.change(role: :member)
    |> Repo.update!()

    conn = get(conn, ~p"/integrations/slack/callback", %{state: state, code: "x"})
    assert redirected_to(conn) == ~p"/teams"
    assert Repo.all(Integration) == []
  end

  test "missing scopes and exchange errors leave the connection unset", ctx do
    for body <- [
          %{ok: false, error: "invalid_code"},
          %{
            ok: true,
            access_token: "secret",
            token_type: "bot",
            scope: "chat:write",
            team: %{id: "T123", name: "Workspace"}
          }
        ] do
      Req.Test.stub(Slack, &Req.Test.json(&1, body))
      conn = post(ctx.conn, ~p"/teams/#{ctx.team}/integrations/slack")
      state = get_session(conn, :slack_oauth_state)
      conn = get(conn, ~p"/integrations/slack/callback", %{state: state, code: "x"})
      assert redirected_to(conn) == ~p"/teams/#{ctx.team}"
      assert Notifications.list_integrations(ctx.scope, ctx.team.id) == []
    end
  end

  test "unconfigured installations cannot start OAuth", ctx do
    Application.put_env(:query_canary, :slack, [])
    conn = post(ctx.conn, ~p"/teams/#{ctx.team}/integrations/slack")
    assert redirected_to(conn) == ~p"/teams/#{ctx.team}"
    assert get_session(conn, :slack_oauth_state) == nil
  end

  test "OAuth endpoints require login", %{team: team} do
    assert build_conn() |> post(~p"/teams/#{team}/integrations/slack") |> redirected_to() ==
             ~p"/users/register"

    assert build_conn() |> get(~p"/integrations/slack/callback") |> redirected_to() ==
             ~p"/users/register"
  end
end
