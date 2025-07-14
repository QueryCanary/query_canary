defmodule QueryCanaryWeb.ServerLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Servers.Server
  alias QueryCanary.Accounts

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
          options={[PostgreSQL: "postgresql", MySQL: "mysql", ClickHouse: "clickhouse"]}
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
          :if={Phoenix.HTML.Form.input_value(@form, :ssh_tunnel) in [true, "true"]}
          class="md:col-span-3 p-4 bg-base-200 rounded-lg mb-2"
        >
          <h3 class="font-semibold mb-2">SSH Tunnel Configuration</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <.input field={@form[:ssh_hostname]} type="text" label="SSH Hostname" />
            <.input field={@form[:ssh_port]} type="number" label="SSH Port" value={22} />
            <.input field={@form[:ssh_username]} type="text" label="SSH Username" />
          </div>
        </div>
        <div
          :if={Phoenix.HTML.Form.input_value(@form, :db_ssl_mode) != "disable"}
          class="md:col-span-3 p-4 bg-base-200 rounded-lg mb-2"
        >
          <h3 class="font-semibold mb-2">SSL Connection Configuration</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="md:col-span-3 mb-2">
              <.input
                field={@form[:db_ssl_mode]}
                type="select"
                label="SSL Mode"
                options={
                  [
                    {"disable - Don't allow a SSL connection", "disable"},
                    {"allow - Use SSL if the server requires it", "allow"}
                    # {"prefer - Try SSL but allow falling back to non-SSL", "prefer"},
                    # {"require - Force SSL, don't allow connection without", "require"},
                    # {"verify-ca - Force SSL, and verify the server has a valid certificate", "verify-ca"},
                    # {"verify-full - Force SSL, and verify the server has a specific SSL certificate", "verify-full"}
                  ]
                }
              />
            </div>
            <%!-- <div class="md:col-span-3 mb-2">
              <.input
                field={@form[:db_ssl_cert]}
                type="textarea"
                label="Client Certificate (PEM or file path)"
              />
            </div>
            <div class="md:col-span-3 mb-2">
              <.input
                field={@form[:db_ssl_key]}
                type="textarea"
                label="Client Key (PEM or file path)"
              />
            </div>
            <div class="md:col-span-3 mb-2">
              <.input
                field={@form[:db_ssl_ca_cert]}
                type="textarea"
                label="CA Certificate (PEM or file path)"
              />
            </div> --%>
          </div>
        </div>
        <div class="md:col-span-3 mb-2">
          <.input
            field={@form[:team_id]}
            type="select"
            options={[{"Personal", nil}] ++ Enum.map(@teams, &{&1.name, &1.id})}
            label="Team"
          />
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
    teams = Accounts.list_teams(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:teams, teams)
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
    server_params =
      Map.drop(server_params, [
        "ssh_public_key",
        "ssh_private_key",
        "ssh_key_type",
        "ssh_key_generated_at"
      ])

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
    if Phoenix.HTML.Form.input_value(form, field) do
      "•••••• previously set ••••••"
    else
      nil
    end
  end
end
