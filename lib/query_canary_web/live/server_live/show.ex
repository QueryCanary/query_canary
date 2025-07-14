defmodule QueryCanaryWeb.ServerLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Connections.SSHKeygen

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <div class="flex items-center gap-2">
          <span class="text-2xl font-semibold">{@server.name}</span>
          <span class="badge badge-primary">{@server.db_engine}</span>
        </div>
        <:subtitle>Database server configuration</:subtitle>
        <:actions>
          <.button navigate={~p"/servers"}>
            <.icon name="hero-arrow-left" /> Back
          </.button>
          <.button variant="primary" navigate={~p"/servers/#{@server}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit server
          </.button>
          <.button variant="success" phx-click="test_connection">
            <.icon name="hero-play" /> Test Connection
          </.button>
          <.button variant="info" phx-click="update_schema">
            <.icon name="hero-circle-stack" /> Update Schema
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mt-6">
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Database Connection</h2>
            <.list>
              <:item title="Name">{@server.name}</:item>
              <:item title="Engine">{@server.db_engine}</:item>
              <:item title="Hostname">{@server.db_hostname}</:item>
              <:item title="Port">{@server.db_port}</:item>
              <:item title="Database">{@server.db_name}</:item>
              <:item title="Username">{@server.db_username}</:item>
              <:item title="SSL Mode">{@server.db_ssl_mode}</:item>
            </.list>
          </div>
        </div>

        <%= if @server.ssh_tunnel do %>
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">
                <.icon name="hero-lock-closed" class="h-5 w-5 mr-1" /> SSH Tunnel
              </h2>
              <.list>
                <:item title="Hostname">{@server.ssh_hostname}</:item>
                <:item title="Port">{@server.ssh_port}</:item>
                <:item title="Username">{@server.ssh_username}</:item>
                <:item title="Public Key">
                  <div class="flex flex-col gap-2">
                    <div class="font-mono text-xs bg-base-300 p-2 rounded max-h-32 overflow-y-auto">
                      <span id="ssh-public-key">{@server.ssh_public_key}</span>
                    </div>
                    <div class="flex gap-2">
                      <%= if @confirming_regenerate do %>
                        <div class="mt-2 p-2 border border-warning bg-warning bg-opacity-10 rounded-md">
                          <p class="text-sm font-medium mb-2">
                            Are you sure? This will invalidate your current key.
                          </p>
                          <div class="flex gap-2">
                            <.button type="button" class="btn-xs" phx-click="cancel_regenerate">
                              Cancel
                            </.button>
                            <.button
                              type="button"
                              class="btn-xs btn-error"
                              phx-click="regenerate_ssh_keys"
                            >
                              Yes, Regenerate
                            </.button>
                          </div>
                        </div>
                      <% else %>
                        <.button type="button" phx-click="confirm_regenerate" variant="primary-sm">
                          <.icon name="hero-arrow-path" class="h-3 w-3 mr-1" /> Regenerate Key
                        </.button>
                      <% end %>
                    </div>
                  </div>
                </:item>
                <:item title="Key Created">{@server.ssh_key_generated_at}</:item>
              </.list>
            </div>
          </div>
        <% end %>
      </div>

      <%= if @connection_result do %>
        <div class={[
          "alert mt-6",
          @connection_result.success && "alert-success",
          !@connection_result.success && "alert-error"
        ]}>
          <%= if @connection_result.success do %>
            <.icon name="hero-check-circle" class="h-6 w-6" />
            <span>Connection successful! {@connection_result.message}</span>
          <% else %>
            <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
            <span>Connection failed: {@connection_result.message}</span>
          <% end %>
        </div>
      <% end %>

      <div class="mt-6">
        <h2 class="text-2xl font-semibold mb-2">Related Checks</h2>
        <.link navigate={~p"/quickstart/check?server_id=#{@server.id}"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Check
        </.link>

        <%= if @checks && length(@checks) > 0 do %>
          <table class="table table-zebra w-full mt-3">
            <thead>
              <tr>
                <th>Check</th>
                <th>Query</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for check <- @checks do %>
                <tr>
                  <td class="font-mono text-xs">{check.name}</td>
                  <td class="font-mono text-xs">{truncate(check.query, 50)}</td>
                  <td>
                    <span :if={check.enabled} class="badge badge-success">Active</span>
                  </td>
                  <td class="text-right">
                    <.link navigate={~p"/checks/#{check}"} class="btn btn-xs">
                      View
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% else %>
          <div class="alert alert-info mt-3">
            <span>No checks configured for this server yet.</span>
          </div>
        <% end %>
      </div>

      <section class="mb-12 space-y-4">
        <h2 class="text-2xl font-semibold mb-2">Current Schema</h2>

        <p>
          This schema is a mapping of your available tables & their fields which is used to help generate the SQL editor. You can update this schema if necessary using the Update Schema button at the top of the page.
        </p>
        <div class="bg-base-200 rounded-lg p-4  max-h-96 overflow-y-auto text-sm font-mono break-words border border-base-300">
          <pre>{Jason.encode!(@server.schema, pretty: true)}</pre>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Servers.subscribe_servers(socket.assigns.current_scope)
    end

    server = Servers.get_server!(socket.assigns.current_scope, id)
    checks = QueryCanary.Checks.list_checks_by_server(socket.assigns.current_scope, server.id)

    {:ok,
     socket
     |> assign(:page_title, "Server Details")
     |> assign(:server, server)
     |> assign(:checks, checks)
     |> assign(:connection_result, nil)
     |> assign(:confirming_regenerate, false)}
  end

  @impl true
  def handle_event("test_connection", _, socket) do
    case QueryCanary.Connections.ConnectionManager.test_connection(socket.assigns.server) do
      {:ok, result} ->
        connection_result = %{
          success: true,
          message:
            "Server time: #{format_cell_value(result.rows |> List.first() |> Map.values() |> List.first())}"
        }

        {:noreply, assign(socket, :connection_result, connection_result)}

      {:error, message} ->
        connection_result = %{
          success: false,
          message: message
        }

        {:noreply, assign(socket, :connection_result, connection_result)}
    end
  end

  def handle_event("update_schema", _, socket) do
    case Servers.update_introspection(socket.assigns.server) do
      {:ok, server} ->
        {:noreply,
         socket
         |> assign(:server, server)
         |> put_flash(:info, "Schema introspection updated")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Schema introspection failed to update")}
    end
  end

  def handle_event("confirm_regenerate", _, socket) do
    {:noreply, assign(socket, :confirming_regenerate, true)}
  end

  def handle_event("cancel_regenerate", _, socket) do
    {:noreply, assign(socket, :confirming_regenerate, false)}
  end

  def handle_event("regenerate_ssh_keys", _, socket) do
    server = socket.assigns.server

    case SSHKeygen.generate_keypair("querycanary.com") do
      {:ok, private_key, public_key} ->
        # Update the server with the new keys
        attrs = %{
          "ssh_public_key" => public_key,
          "ssh_private_key" => private_key,
          "ssh_key_type" => "ed25519",
          "ssh_key_generated_at" => DateTime.utc_now()
        }

        case Servers.update_server(socket.assigns.current_scope, server, attrs) do
          {:ok, updated_server} ->
            {:noreply,
             socket
             |> assign(:server, updated_server)
             |> assign(:confirming_regenerate, false)
             |> put_flash(
               :info,
               "SSH key regenerated successfully. Don't forget to update your server's authorized_keys file!"
             )}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:confirming_regenerate, false)
             |> put_flash(:error, "Failed to update server with new SSH keys")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:confirming_regenerate, false)
         |> put_flash(:error, "Failed to generate new SSH keys: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(
        {:updated, %QueryCanary.Servers.Server{id: id} = server},
        %{assigns: %{server: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :server, server)}
  end

  def handle_info(
        {:deleted, %QueryCanary.Servers.Server{id: id}},
        %{assigns: %{server: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current server was deleted.")
     |> push_navigate(to: ~p"/servers")}
  end

  def handle_info({type, %QueryCanary.Servers.Server{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  # Helper functions
  defp truncate(text, max_length) when is_binary(text) do
    if String.length(text) > max_length do
      "#{String.slice(text, 0, max_length)}..."
    else
      text
    end
  end

  defp truncate(nil, _), do: ""

  defp format_cell_value(nil), do: "<NULL>"
  defp format_cell_value(value) when is_binary(value), do: value
  defp format_cell_value(value) when is_number(value), do: "#{value}"

  defp format_cell_value(value) when is_boolean(value) do
    if value, do: "true", else: "false"
  end

  defp format_cell_value(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_cell_value(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_cell_value(value), do: inspect(value)
end
