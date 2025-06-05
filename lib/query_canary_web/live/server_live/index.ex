defmodule QueryCanaryWeb.ServerLive.Index do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Database Servers
        <:actions>
          <.button variant="primary" navigate={~p"/quickstart"}>
            <.icon name="hero-plus" /> New Server
          </.button>
        </:actions>
      </.header>

      <.table
        id="servers"
        rows={@streams.servers}
        row_click={fn {_id, server} -> JS.navigate(~p"/servers/#{server}") end}
      >
        <:col :let={{_id, server}} label="Owner">
          {if(server.user_id, do: "Personal", else: "Team")}
        </:col>
        <:col :let={{_id, server}} label="Name">{server.name}</:col>
        <:col :let={{_id, server}} label="Engine">{server.db_engine}</:col>
        <:col :let={{_id, server}} label="Hostname">{server.db_hostname}</:col>
        <:action :let={{_id, server}}>
          <div class="sr-only">
            <.link navigate={~p"/servers/#{server}"}>Show</.link>
          </div>
          <.link navigate={~p"/servers/#{server}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, server}}>
          <.link
            phx-click={JS.push("delete", value: %{id: server.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Servers.subscribe_servers(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Database Servers")
     |> stream(:servers, Servers.list_servers(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    server = Servers.get_server!(socket.assigns.current_scope, id)
    {:ok, _} = Servers.delete_server(socket.assigns.current_scope, server)

    {:noreply, stream_delete(socket, :servers, server)}
  end

  @impl true
  def handle_info({type, %QueryCanary.Servers.Server{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :servers, Servers.list_servers(socket.assigns.current_scope), reset: true)}
  end
end
