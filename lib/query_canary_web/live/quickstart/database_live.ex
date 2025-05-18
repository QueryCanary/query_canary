defmodule QueryCanaryWeb.Quickstart.DatabaseLive do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Servers.Server

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

        <div class="collapse bg-base-100 border-base-300 border">
          <input type="checkbox" />
          <div class="collapse-title font-semibold">
            How do I create a new secure database user for QueryCanary?
          </div>
          <div class="collapse-content text-sm space-y-4">
            <p>
              To allow QueryCanary to run integrity checks safely, we recommend creating a dedicated read-only Postgres user with limited permissions.
            </p>

            <div class="alert alert-info text-sm">
              <span>
                This user will only be able to connect, read data, and run SELECT queries. It cannot modify your database.
              </span>
            </div>

            <div class="bg-base-200 rounded-lg p-4  max-h-96 overflow-y-auto text-sm font-mono break-words border border-base-300">
              <pre>-- 1. Create a dedicated read-only user
    CREATE USER querycanary_reader WITH PASSWORD 'your_secure_password';

    -- 2. Allow it to connect to your database
    GRANT CONNECT ON DATABASE your_database TO querycanary_reader;

    -- 3. Grant usage on the schema you want to monitor (typically public)
    GRANT USAGE ON SCHEMA public TO querycanary_reader;

    -- 4. Grant read-only access to all existing tables
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO querycanary_reader;

    -- 5. Ensure access to future tables too
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO querycanary_reader;
    </pre>
            </div>

            <div class="alert alert-error">
              <span>
                Replace <code>your_secure_password</code>
                with a strong unique password, and <code>your_database</code>
                if your DB isn't named "postgres". Repeat the schema-related lines if you use multiple schemas.
              </span>
            </div>
          </div>
        </div>

        <.form
          for={@form}
          id="server-form"
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 md:grid-cols-3 gap-4"
        >
          <.input type="hidden" field={@form[:db_engine]} value="postgresql" />

          <div class="md:col-span-3">
            <div class="grid grid-cols-1 gap-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-base font-semibold">Database Engine</span>
                </label>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <label class="cursor-pointer flex flex-col items-center border rounded-lg p-4 border-base-300 bg-base-200">
                    <img
                      src="https://raw.githubusercontent.com/devicons/devicon/master/icons/postgresql/postgresql-original.svg"
                      alt="PostgreSQL"
                      class="w-8 h-8 mb-2"
                    />
                    <span>PostgreSQL</span>
                  </label>

                  <label class="flex flex-col items-center border rounded-lg p-4 border-base-300 opacity-60 relative">
                    <input type="radio" disabled class="hidden" />
                    <img
                      src="https://raw.githubusercontent.com/devicons/devicon/master/icons/mysql/mysql-original.svg"
                      alt="MySQL"
                      class="w-8 h-8 mb-2"
                    />
                    <span>MySQL</span>
                    <span class="badge badge-warning text-xs absolute top-1 right-1">
                      Coming Soon
                    </span>
                  </label>

                  <label class="flex flex-col items-center border rounded-lg p-4 border-base-300 opacity-60 relative">
                    <input type="radio" disabled class="hidden" />
                    <img
                      src="https://raw.githubusercontent.com/devicons/devicon/master/icons/microsoftsqlserver/microsoftsqlserver-plain.svg"
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
                    <img
                      src="https://raw.githubusercontent.com/devicons/devicon/master/icons/mongodb/mongodb-original.svg"
                      alt="MongoDB"
                      class="w-8 h-8 mb-2"
                    />
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

          <footer class="md:col-span-3 space-y-6  ">
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

    {:ok,
     socket
     |> assign(:page_title, "QueryCanary Quickstart")
     |> assign(:server, server)
     |> assign(:connection_error, nil)
     |> assign(
       :form,
       to_form(Servers.change_server(socket.assigns.current_scope, server))
     )}
  end

  @impl true
  def handle_params(%{"server_id" => server_id}, _uri, socket) do
    case Servers.get_server(socket.assigns.current_scope, server_id) do
      %Server{} = server ->
        {:noreply,
         socket
         |> assign(:server, server)
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
    server =
      if socket.assigns.server.id do
        Servers.update_server(
          socket.assigns.current_scope,
          socket.assigns.server,
          server_params
        )
      else
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

  defp password_placeholder(form, field) do
    if Phoenix.HTML.Form.input_value(form, field) do
      "•••••• previously set ••••••"
    else
      nil
    end
  end
end
