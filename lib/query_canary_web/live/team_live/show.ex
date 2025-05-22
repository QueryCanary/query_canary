defmodule QueryCanaryWeb.TeamLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Team {@team.id}
        <:subtitle>This is a team record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/teams"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}
            variant="primary"
            navigate={~p"/teams/#{@team}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit team
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@team.name}</:item>
      </.list>

      <div class="mt-8">
        <div :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}>
          <h3 class="text-lg font-semibold">Invite Users</h3>
          <.form for={@invite_form} id="invite-form" phx-submit="invite_user">
            <.input field={@invite_form[:email]} type="email" label="User Email" />
            <footer>
              <.button phx-disable-with="Inviting..." variant="primary">Invite</.button>
            </footer>
          </.form>
        </div>

        <div class="mt-4">
          <h4 class="text-md font-semibold">Users</h4>
          <.table id="users" rows={@users}>
            <:col :let={{user, _role}} label="Email">{user.email}</:col>
            <:col :let={{user, role}} label="Role">{role}</:col>
            <:action :let={{user, _role}}>
              <.link
                :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}
                phx-click={JS.push("remove_user", value: %{id: user.id}) |> hide("##{user.id}")}
                data-confirm="Are you sure?"
              >
                Remove
              </.link>
            </:action>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Accounts.subscribe_teams(socket.assigns.current_scope)
    end

    team = Accounts.get_team!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, "Show Team")
     |> assign(:team, team)
     |> assign(:invite_form, to_form(%{email: ""}))
     |> assign(:users, Accounts.list_team_users(socket.assigns.current_scope, team))}
  end

  @impl true
  def handle_params(_, _, %{assigns: %{live_action: :accept}} = socket) do
    Accounts.accept_team_invite(socket.assigns.current_scope, socket.assigns.team)

    {:noreply, push_patch(socket, to: ~p"/checks")}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:updated, %QueryCanary.Accounts.Team{id: id} = team},
        %{assigns: %{team: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :team, team)}
  end

  def handle_info(
        {:deleted, %QueryCanary.Accounts.Team{id: id}},
        %{assigns: %{team: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current team was deleted.")
     |> push_navigate(to: ~p"/teams")}
  end

  def handle_info({type, %QueryCanary.Accounts.Team{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  @impl true
  def handle_event("invite_user", %{"email" => email}, socket) do
    existing_user = Accounts.get_user_by_email(email)

    case Accounts.invite_user_to_team(socket.assigns.current_scope, socket.assigns.team, email) do
      {:ok, user} ->
        if is_nil(existing_user) do
          Accounts.deliver_invite_register_instructions(
            user,
            socket.assigns.team,
            &url(~p"/users/log-in/#{&1}")
          )
        else
          Accounts.deliver_invite_instructions(
            user,
            socket.assigns.team,
            &url(~p"/teams/#{&1}/accept")
          )
        end

        {:noreply,
         socket
         |> put_flash(:info, "#{user.email} has been invited.")
         |> assign(
           :users,
           Accounts.list_team_users(socket.assigns.current_scope, socket.assigns.team)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to invite user: #{reason}")}
    end
  end

  def handle_event("remove_user", %{"id" => id}, socket) do
    case Accounts.remove_user_from_team(socket.assigns.current_scope, socket.assigns.team, id) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User removed.")
         |> assign(
           :users,
           Accounts.list_team_users(socket.assigns.current_scope, socket.assigns.team)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove user: #{reason}")}
    end
  end
end
