defmodule QueryCanaryWeb.ServerLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Servers.Server

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage server records in your database.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="server-form"
        phx-change="validate"
        phx-submit="save"
        class="grid grid-cols-1 md:grid-cols-3 gap-4"
      >
        <div class="md:col-span-2">
          <.input field={@form[:name]} type="text" label="Friendly Name" autofocus />
        </div>
        <.input
          field={@form[:db_engine]}
          type="select"
          options={[PostgreSQL: "postgresql", MySQL: "mysql"]}
          label="Engine"
        />
        <div class="md:col-span-2">
          <.input field={@form[:db_hostname]} type="text" label="Hostname" />
        </div>
        <.input field={@form[:db_port]} type="number" label="Port" />
        <.input field={@form[:db_username]} type="text" label="Username" />
        <.input
          field={@form[:db_password_input]}
          type="password"
          label="Password"
          placeholder={password_placeholder(@form, :db_password)}
        />
        <.input field={@form[:db_name]} type="text" label="Database" />
        <div class="md:col-span-3 mb-2">
          <div class="flex items-center">
            <.input field={@form[:ssh_tunnel]} type="checkbox" label="Use SSH Tunnel?" />
          </div>
        </div>
        <div
          :if={Phoenix.HTML.Form.input_value(@form, :ssh_tunnel) == true}
          class="md:col-span-3 p-4 bg-base-200 rounded-lg mb-2"
        >
          <h3 class="font-semibold mb-2">SSH Tunnel Configuration</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="md:col-span-2">
              <.input field={@form[:ssh_hostname]} type="text" label="SSH Hostname" />
            </div>
            <.input field={@form[:ssh_port]} type="number" label="SSH Port" value={22} />
            <.input field={@form[:ssh_username]} type="text" label="SSH Username" />

            <div class="md:col-span-3">
              <.input
                field={@form[:ssh_password_input]}
                type="password"
                label="SSH Password"
                placeholder={password_placeholder(@form, :ssh_password)}
              />
              <.input
                field={@form[:ssh_private_key_input]}
                type="textarea"
                rows="3"
                label="SSH Private Key"
                class="font-mono"
              />
            </div>
            <.input
              field={@form[:ssh_key_passphrase]}
              type="password"
              label="Key Passphrase (optional)"
            />
          </div>
        </div>
        <footer class="md:col-span-2">
          <.button phx-disable-with="Connecting..." variant="primary" class="w-full">
            Save Server
          </.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    server = Servers.get_server!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Server")
    |> assign(:server, server)
    |> assign(:form, to_form(Servers.change_server(socket.assigns.current_scope, server)))
  end

  defp apply_action(socket, :new, _params) do
    server = %Server{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Server")
    |> assign(:server, server)
    |> assign(:form, to_form(Servers.change_server(socket.assigns.current_scope, server)))
  end

  @impl true
  def handle_event("validate", %{"server" => server_params}, socket) do
    changeset =
      Servers.change_server(socket.assigns.current_scope, socket.assigns.server, server_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"server" => server_params}, socket) do
    save_server(socket, socket.assigns.live_action, server_params)
  end

  defp save_server(socket, :edit, server_params) do
    case Servers.update_server(socket.assigns.current_scope, socket.assigns.server, server_params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Server updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, server)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_server(socket, :new, server_params) do
    case Servers.create_server(socket.assigns.current_scope, server_params) do
      {:ok, server} ->
        {:noreply,
         socket
         |> put_flash(:info, "Server created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, server)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _server), do: ~p"/servers"
  defp return_path(_scope, "show", server), do: ~p"/servers/#{server}"

  defp password_placeholder(form, field) do
    if Phoenix.HTML.Form.input_value(form, field) |> dbg() do
      "•••••• previously set ••••••"
    else
      nil
    end
  end
end
