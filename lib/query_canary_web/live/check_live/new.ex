defmodule QueryCanaryWeb.CheckLive.New do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-lg mx-auto py-12">
        <.header class="text-center">
          Create a New Check
          <:subtitle>
            Choose a database server to get started
          </:subtitle>
        </.header>

        <div class="mt-8 bg-base-100 shadow-lg rounded-lg p-8">
          <%= if Enum.empty?(@server_options) do %>
            <div class="mt-8 text-center">
              <div class="bg-base-200 rounded-full p-4 inline-block mb-4">
                <.icon name="hero-server" class="w-12 h-12 opacity-40" />
              </div>
              <p class="text-base-content/70 mb-6">
                You need to set up a database server before you can create checks.
              </p>
              <.button navigate={~p"/quickstart"} variant="primary">
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> Add Your First Server
              </.button>
            </div>
          <% else %>
            <.form for={@form} phx-submit="select_server" class="space-y-6">
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-lg">Select a Database Server</span>
                </label>
                <.input
                  field={@form[:server_id]}
                  type="select"
                  options={@server_options}
                  prompt="Choose a server to monitor"
                  required
                />
                <div class="text-xs text-base-content/60 mt-2">
                  Or
                  <.link navigate={~p"/quickstart"} class="link link-primary">
                    create a new server
                  </.link>
                  first
                </div>
              </div>

              <.button type="submit" variant="primary" class="w-full">
                <.icon name="hero-rocket-launch" class="w-5 h-5 mr-2" /> Continue to Quick Setup
              </.button>
            </.form>
          <% end %>
        </div>

        <div class="mt-8">
          <div class="divider">OR</div>
          <p class="text-center text-base-content/70 mb-4">
            Go back to view your existing checks
          </p>
          <div class="flex justify-center">
            <.button navigate={~p"/checks"}>
              <.icon name="hero-arrow-left" class="w-4 h-4 mr-2" /> Back to Checks
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    servers = Servers.list_servers(socket.assigns.current_scope)
    server_options = Enum.map(servers, &{&1.name, &1.id})

    form = to_form(%{"server_id" => nil})

    {:ok,
     socket
     |> assign(:page_title, "Create New Check")
     |> assign(:server_options, server_options)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("select_server", %{"server_id" => server_id}, socket) when server_id != "" do
    {:noreply, push_navigate(socket, to: ~p"/quickstart/check?server_id=#{server_id}")}
  end

  @impl true
  def handle_event("select_server", _params, socket) do
    {:noreply, socket |> put_flash(:error, "Please select a server to continue")}
  end
end
