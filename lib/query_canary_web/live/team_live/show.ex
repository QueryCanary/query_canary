defmodule QueryCanaryWeb.TeamLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <.icon name="hero-users" class="h-6 w-6" /> {@team.name}
        <:subtitle>Manage your team, invite users, and view team details.</:subtitle>
        <:actions>
          <.button navigate={~p"/teams"}>
            <.icon name="hero-arrow-left" /> Back to Teams
          </.button>
          <.button
            :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}
            variant="primary"
            navigate={~p"/teams/#{@team}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit Team
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="card bg-base-200 p-6">
          <h2 class="text-lg font-semibold mb-4">Team Details</h2>
          <.list>
            <:item title="Name">{@team.name}</:item>
            <:item title="Created At">{format_datetime(@team.inserted_at)}</:item>
            <:item title="Plan">{@team.plan}</:item>
            <:item title="Billing Status">{@team.billing_status}</:item>
            <:item title="Plan Started At">{@team.billing_started_at}</:item>
            <:item title="Plan Renewing At">{@team.billing_renewal_at}</:item>
          </.list>
        </div>
        <div class="card bg-base-200 max-w-md w-full text-center space-y-6 p-8">
          <h1 class="text-3xl font-bold">Paid Team</h1>
          <p :if={@team.plan == :free} class="text-sm opacity-70">
            Teams on QueryCanary require a paid plan. Once you subscribe, you'll get access to more checks, more database server connections, more history, and the ability to invite other members of your team to QueryCanary.
          </p>
          <div :if={@team.plan == :paid} role="alert" class="alert alert-success">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6 shrink-0 stroke-current"
              fill="none"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <span>You're getting full access! Thank you for being a subscriber.</span>
          </div>

          <ul class="space-y-3 text-sm w-full">
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">100 checks</span>
            </li>
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">10 database connections</span>
            </li>
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">Every minute scheduling</span>
            </li>
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">Email + Slack alerts</span>
            </li>
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">365-day rolling history</span>
            </li>
            <li class="flex items-center">
              <.green_check />
              <span class="font-medium">Team members</span>
            </li>
          </ul>

          <div class="">
            <.button :if={@team.plan == :free} phx-click="start_checkout" variant="primary">
              Upgrade to a Paid Team
            </.button>
            <p :if={@team.plan == :paid}>
              Want to cancel? No problem, shoot a quick email to
              <a class="link link-hover" href="mailto:support@querycanary.com" target="_blank">
                support@querycanary.com
              </a>
            </p>
          </div>
        </div>
      </div>
      
    <!-- Team Members -->
      <div class="mt-8 space-y-4">
        <h2 class="text-lg font-semibold mb-4">Team Members</h2>
        <.table id="users" rows={@users}>
          <:col :let={{user, _role}} label="Email">{user.email}</:col>
          <:col :let={{_user, role}} label="Role">{String.capitalize(to_string(role))}</:col>
          <:action :let={{user, _role}}>
            <.link
              :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}
              phx-click={JS.push("remove_user", value: %{id: user.id}) |> hide("##{user.id}")}
              data-confirm="Are you sure?"
              class="text-error"
            >
              Remove
            </.link>
          </:action>
        </.table>
        <div
          :if={Accounts.user_has_access_to_team?(@current_scope.user.id, @team.id, :admin)}
          class="card bg-base-200 p-6"
        >
          <h2 class="text-lg font-semibold mb-4">Invite Users</h2>
          <.form for={@invite_form} id="invite-form" phx-submit="invite_user">
            <.input field={@invite_form[:email]} type="email" label="User Email" />
            <footer>
              <.button phx-disable-with="Inviting..." variant="primary">Send Invite</.button>
            </footer>
          </.form>
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

  def handle_params(%{"session_id" => session_id}, _uri, socket) do
    case Stripe.Checkout.Session.retrieve(session_id) do
      {:ok, %Stripe.Checkout.Session{} = session} ->
        # TODO: Check for team match
        # socket.assigns.team.id = session.client_reference_id

        # For laziness, we'll expire the subscription in exactly 30 days
        expires_at = DateTime.utc_now() |> DateTime.add(86_400 * 30)

        {:ok, _team} =
          QueryCanary.Accounts.update_team_billing(
            socket.assigns.current_scope,
            socket.assigns.team,
            %{
              stripe_customer_id: session.customer,
              stripe_subscription_id: session.subscription,
              plan: "paid",
              billing_status: session.payment_status,
              billing_started_at: DateTime.utc_now(),
              billing_renewal_at: expires_at
            }
          )

        {:noreply,
         socket
         |> put_flash(:success, "Successfully subscribed!")
         |> push_patch(to: ~p"/teams/#{socket.assigns.team}")}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to subscribe.")
         |> push_patch(to: ~p"/teams/#{socket.assigns.team}")}
    end
  end

  def handle_params(%{"stripe_cancel" => _}, _uri, socket) do
    {:noreply,
     socket
     |> push_patch(to: ~p"/teams/#{socket.assigns.team}")
     |> put_flash(:error, "Stripe checkout cancelled!")}
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

  def handle_event("start_checkout", _, socket) do
    user = socket.assigns.current_scope.user
    team = socket.assigns.team

    case create_stripe_checkout_session(user, team) do
      {:ok, %Stripe.Checkout.Session{url: session_url}} ->
        {:noreply, redirect(socket, external: session_url)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start checkout: #{inspect(reason)}")}
    end
  end

  defp create_stripe_checkout_session(user, team) do
    Stripe.Checkout.Session.create(%{
      client_reference_id: team.id,
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [
        %{
          price: "price_1RPlcJPFoGavtXofodxe4qBa",
          quantity: 1
        }
      ],
      success_url: url(~p"/teams/#{team}?session_id={CHECKOUT_SESSION_ID}"),
      cancel_url: url(~p"/teams/#{team}?stripe_cancel=true"),
      customer_email: user.email
    })
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime),
    do: datetime

  defp green_check(assigns) do
    ~H"""
    <svg class="w-5 h-5 mr-2 text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
    </svg>
    """
  end
end
