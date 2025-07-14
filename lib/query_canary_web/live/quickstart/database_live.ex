defmodule QueryCanaryWeb.Quickstart.DatabaseLive do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Servers.Server
  alias QueryCanary.Connections.SSHKeygen

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-3xl font-bold mb-6">QueryCanary Quickstart</h1>

      <section class="mb-12 space-y-4">
        <h2 class="text-2xl font-semibold mb-2">1. Connect to Your Database</h2>
        <p class="mb-4">
          Enter your database connection details below. It's strongly recommended to create a specific user for QueryCanary, with permissions limited to connect & select.
        </p>

        <.form
          for={@form}
          id="server-form"
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 md:grid-cols-3 gap-4"
        >
          <div class="md:col-span-3">
            <div class="grid grid-cols-1 gap-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-base font-semibold">Database Engine</span>
                </label>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <label class={[
                    "cursor-pointer flex flex-col items-center border rounded-lg p-4 border-base-300",
                    if(Phoenix.HTML.Form.input_value(@form, :db_engine) == "postgresql",
                      do: "bg-base-200 ring-2 ring-primary",
                      else: "bg-base-100"
                    )
                  ]}>
                    <input
                      type="radio"
                      id={Phoenix.HTML.Form.input_id(@form, :db_engine, "postgresql")}
                      name={Phoenix.HTML.Form.input_name(@form, :db_engine)}
                      value="postgresql"
                      checked={Phoenix.HTML.Form.input_value(@form, :db_engine) == "postgresql"}
                      class="hidden"
                    />
                    <img
                      src={~p"/images/postgresql-original.svg"}
                      alt="PostgreSQL"
                      class="w-8 h-8 mb-2"
                    />
                    <span>PostgreSQL</span>
                  </label>

                  <label class={[
                    "cursor-pointer flex flex-col items-center border rounded-lg p-4 border-base-300",
                    if(Phoenix.HTML.Form.input_value(@form, :db_engine) == "mysql",
                      do: "bg-base-200 ring-2 ring-primary",
                      else: "bg-base-100"
                    )
                  ]}>
                    <input
                      type="radio"
                      id={Phoenix.HTML.Form.input_id(@form, :db_engine, "mysql")}
                      name={Phoenix.HTML.Form.input_name(@form, :db_engine)}
                      value="mysql"
                      checked={Phoenix.HTML.Form.input_value(@form, :db_engine) == "mysql"}
                      class="hidden"
                    />
                    <img src={~p"/images/mysql-original.svg"} alt="MySQL" class="w-8 h-8 mb-2" />
                    <span>MySQL</span>
                  </label>

                  <label class={[
                    "cursor-pointer flex flex-col items-center border rounded-lg p-4 border-base-300",
                    if(Phoenix.HTML.Form.input_value(@form, :db_engine) == "clickhouse",
                      do: "bg-base-200 ring-2 ring-primary",
                      else: "bg-base-100"
                    )
                  ]}>
                    <input
                      type="radio"
                      id={Phoenix.HTML.Form.input_id(@form, :db_engine, "clickhouse")}
                      name={Phoenix.HTML.Form.input_name(@form, :db_engine)}
                      value="clickhouse"
                      checked={Phoenix.HTML.Form.input_value(@form, :db_engine) == "clickhouse"}
                      class="hidden"
                    />
                    <img src={~p"/images/clickhouse.svg"} alt="ClickHouse" class="w-8 h-8 mb-2" />
                    <span>ClickHouse</span>
                  </label>

                  <label class="flex flex-col items-center border rounded-lg p-4 border-base-300 opacity-60 relative">
                    <input type="radio" disabled class="hidden" />
                    <img
                      src={~p"/images/microsoftsqlserver-plain.svg"}
                      alt="SQL Server"
                      class="w-8 h-8 mb-2"
                    />
                    <span>SQL Server</span>
                    <span class="badge badge-warning text-xs absolute top-1 right-1">
                      Coming Soon
                    </span>
                  </label>

                  <label class="flex flex-col items-center border rounded-lg p-4 border-base-300 opacity-60 relative">
                    <input type="radio" disabled class="hidden" />
                    <img src={~p"/images/mongodb-original.svg"} alt="MongoDB" class="w-8 h-8 mb-2" />
                    <span>MongoDB</span>
                    <span class="badge badge-warning text-xs absolute top-1 right-1">
                      Coming Soon
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </div>

          <div class="md:col-span-3">
            <.link
              :if={Phoenix.HTML.Form.input_value(@form, :db_engine) == "postgresql"}
              class="link link-hover text-lg link-info"
              target="_blank"
              navigate={~p"/docs/servers/postgresql"}
            >
              PostgreSQL Setup Documentation <.icon name="hero-arrow-right" />
            </.link>
            <.link
              :if={Phoenix.HTML.Form.input_value(@form, :db_engine) == "mysql"}
              class="link link-hover text-lg link-info"
              target="_blank"
              navigate={~p"/docs/servers/mysql"}
            >
              MySQL Setup Documentation <.icon name="hero-arrow-right" />
            </.link>
            <.link
              :if={Phoenix.HTML.Form.input_value(@form, :db_engine) == "clickhouse"}
              class="link link-hover text-lg link-info"
              target="_blank"
              navigate={~p"/docs/servers/clickhouse"}
            >
              ClickHouse Setup Documentation <.icon name="hero-arrow-right" />
            </.link>
          </div>

          <div class="md:col-span-3">
            <.input field={@form[:name]} type="text" label="Friendly Name" autofocus />
          </div>
          <div class="md:col-span-2">
            <.input field={@form[:db_hostname]} type="text" label="Hostname" />
          </div>
          <.input field={@form[:db_port]} type="number" label="Port" value="5432" />
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
            <h3 class="font-semibold mb-2">
              SSH Tunnel Configuration
              <.link
                navigate={~p"/docs/servers/ssh-tunnel"}
                target="_blank"
                class="link link-hover link-info text-sm"
              >
                SSH Tunnel Setup Documentation <.icon name="hero-arrow-right" />
              </.link>
            </h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <.input field={@form[:ssh_hostname]} type="text" label="SSH Hostname" />
              <.input field={@form[:ssh_port]} type="number" label="SSH Port" value={22} />
              <.input field={@form[:ssh_username]} type="text" label="SSH Username" />
            </div>

            <div class="mt-4 border-t pt-4 border-base-300">
              <h4 class="font-medium mb-2">SSH Key Authentication</h4>

              <div class="space-y-4">
                <p>
                  We've generated a keypair for QueryCanary to access your server to create the SSH Tunnel for your Database. Add this public key to your server's
                  <code class="font-mono">~/.ssh/authorized_keys</code>
                  file to authorize the connection.
                </p>

                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Public Key</span>
                  </label>
                  <div class="bg-base-200 rounded-lg p-4  max-h-96 overflow-y-auto text-sm font-mono break-words border border-base-300">
                    <pre>{@ssh_public_key}</pre>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- <div class="md:col-span-3 mb-2">
            <div class="flex items-center">
              <.input field={@form[:db_ssl]} type="checkbox" label="Use SSL?" />
            </div>
          </div>
          <.input
            field={@form[:db_ssl_opts]}
            type="textarea"
            label="SSL Options (JSON, optional)"
            placeholder='{"verify": :verify_peer}'
          /> --%>

          <footer class="md:col-span-3 space-y-6">
            <div :if={@connection_error} class="alert alert-error">
              <span>
                {inspect(@connection_error)}
              </span>
            </div>
            <.button phx-disable-with="Connecting..." variant="primary" class="w-full">
              Test Connection
            </.button>
          </footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    server = %Server{user_id: socket.assigns.current_scope.user.id}

    # Generate SSH keys when the component mounts
    # These will be stored in the session and used when saving
    {public_key, private_key} = generate_ssh_keys()

    {:ok,
     socket
     |> assign(:page_title, "QueryCanary Quickstart")
     |> assign(:server, server)
     |> assign(:connection_error, nil)
     |> assign(:ssh_public_key, public_key)
     |> assign(:ssh_private_key, private_key)
     |> assign(
       :form,
       to_form(Servers.change_server(socket.assigns.current_scope, server))
     )}
  end

  @impl true
  def handle_params(%{"server_id" => server_id}, _uri, socket) do
    case Servers.get_server(socket.assigns.current_scope, server_id) do
      %Server{} = server ->
        # For existing servers, check if we already have a generated key
        {public_key, private_key} =
          if server.ssh_public_key do
            {server.ssh_public_key, nil}
          else
            # Generate new keys for existing servers that don't have them yet
            generate_ssh_keys()
          end

        {:noreply,
         socket
         |> assign(:server, server)
         |> assign(:ssh_public_key, public_key)
         |> assign(:ssh_private_key, private_key)
         |> assign(
           :form,
           to_form(Servers.change_server(socket.assigns.current_scope, server))
         )}

      nil ->
        {:noreply,
         socket
         |> push_patch(to: ~p"/quickstart")
         |> put_flash(:error, "Server not found")}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"server" => server_params}, socket) do
    changeset =
      Servers.change_server(
        socket.assigns.current_scope,
        socket.assigns.server,
        server_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"server" => server_params}, socket) do
    # Add the pre-generated SSH keys to the server params if SSH tunnel is enabled
    server_params =
      Map.drop(server_params, [
        "ssh_public_key",
        "ssh_private_key",
        "ssh_key_type",
        "ssh_key_generated_at"
      ])

    server =
      if socket.assigns.server.id do
        Servers.update_server(
          socket.assigns.current_scope,
          socket.assigns.server,
          server_params
        )
      else
        server_params =
          Map.merge(server_params, %{
            "ssh_public_key" => socket.assigns.ssh_public_key,
            "ssh_private_key" => socket.assigns.ssh_private_key,
            "ssh_key_type" => "secp256r1",
            "ssh_key_generated_at" => DateTime.utc_now() |> DateTime.to_string()
          })

        Servers.create_server(socket.assigns.current_scope, server_params)
      end

    case server do
      {:ok, server} ->
        case QueryCanary.Connections.ConnectionTester.diagnose_connection(server) do
          {:ok, _query} ->
            Servers.update_introspection(server)

            {:noreply,
             socket
             |> assign(:server, server)
             |> assign(:connection_error, false)
             |> put_flash(:info, "Server created successfully")
             |> push_navigate(to: ~p"/quickstart/check?server_id=#{server.id}")}

          {:error, %{type: error_type}} ->
            {:noreply,
             socket
             |> assign(:server, server)
             |> assign(
               :connection_error,
               "Could not connect to your database: #{inspect(error_type)}"
             )
             |> put_flash(:info, "Server created successfully, but failed to connect")
             |> push_patch(to: ~p"/quickstart?server_id=#{server.id}")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Generate SSH keys with a predictable comment to ensure consistency
  defp generate_ssh_keys do
    comment = "querycanary.com"

    case SSHKeygen.generate_keypair(comment) do
      {:ok, private_key, public_key} ->
        {public_key, private_key}

      _ ->
        # Fallback in case the key generation fails - should never happen
        raise "SSH Key generation failed"
    end
  end

  defp password_placeholder(form, field) do
    if Phoenix.HTML.Form.input_value(form, field) do
      "•••••• previously set ••••••"
    else
      nil
    end
  end
end
