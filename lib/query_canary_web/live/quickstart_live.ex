defmodule QueryCanaryWeb.QuickstartLive do
  alias QueryCanary.Checks
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Servers
  alias QueryCanary.Servers.Server

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-3xl font-bold mb-6">QueryCanary Quickstart</h1>
      
    <!-- Step 1: Choose Database Type -->
      <section class="mb-12">
        <h2 class="text-2xl font-semibold mb-2">1. Choose Your Database Engine</h2>
        <p class="mb-4">Select your database type to begin configuring your connection.</p>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-6">
          <.link
            patch={~p"/quickstart?engine=postgresql"}
            class={[
              "btn btn-outline flex flex-col items-center p-4 h-full",
              if(@engine == "postgresql", do: "btn-active")
            ]}
          >
            <img
              src="https://raw.githubusercontent.com/devicons/devicon/master/icons/postgresql/postgresql-original.svg"
              alt="PostgreSQL"
              class="w-8 h-8 mb-2"
            /> PostgreSQL
          </.link>
          <.link
            patch={~p"/quickstart?engine=mysql"}
            class={[
              "btn btn-outline flex flex-col items-center p-4 h-full",
              if(@engine == "mysql", do: "btn-active")
            ]}
          >
            <img
              src="https://raw.githubusercontent.com/devicons/devicon/master/icons/mysql/mysql-original.svg"
              alt="MySQL"
              class="w-8 h-8 mb-2"
            /> MySQL
          </.link>
          <.link
            patch={~p"/quickstart?engine=sqlserver"}
            class="btn btn-disabled flex flex-col items-center p-4 relative h-full"
          >
            <img
              src="https://raw.githubusercontent.com/devicons/devicon/master/icons/microsoftsqlserver/microsoftsqlserver-plain.svg"
              alt="SQL Server"
              class="w-8 h-8 mb-2"
            /> SQL Server
            <span class="badge badge-warning text-xs absolute top-1 right-1">Coming Soon</span>
          </.link>
          <.link
            patch={~p"/quickstart?engine=mongodb"}
            class="btn btn-disabled flex flex-col items-center p-4 relative h-full"
          >
            <img
              src="https://raw.githubusercontent.com/devicons/devicon/master/icons/mongodb/mongodb-original.svg"
              alt="MongoDB"
              class="w-8 h-8 mb-2 opacity-50"
            /> MongoDB
            <span class="badge badge-warning text-xs absolute top-1 right-1">Coming Soon</span>
          </.link>
        </div>
      </section>
      
    <!-- Step 2: Connect to SQL -->
      <section :if={@engine} class="mb-12">
        <h2 class="text-2xl font-semibold mb-2">2. Connect to Your Database</h2>
        <p class="mb-4">
          Enter your database connection details below. It's strongly recommended to create a specific user for QueryCanary, with permissions limited to connect & select.
        </p>

        <.form
          for={@server_form}
          id="server-form"
          phx-change="validate_server"
          phx-submit="save_server"
          class="grid grid-cols-1 md:grid-cols-3 gap-4"
        >
          <.input field={@server_form[:db_engine]} type="hidden" value={@engine} />
          <div class="md:col-span-2">
            <.input field={@server_form[:name]} type="text" label="Friendly Name" autofocus />
          </div>
          <div class="md:col-span-2">
            <.input field={@server_form[:db_hostname]} type="text" label="Hostname" />
          </div>
          <.input field={@server_form[:db_port]} type="number" label="Port" />
          <.input field={@server_form[:db_username]} type="text" label="Username" />
          <.input
            field={@server_form[:db_password_input]}
            type="password"
            label="Password"
            placeholder={password_placeholder(@server_form, :db_password)}
          />
          <.input field={@server_form[:db_name]} type="text" label="Database" />
          <div class="md:col-span-3 mb-2">
            <div class="flex items-center">
              <.input field={@server_form[:ssh_tunnel]} type="checkbox" label="Use SSH Tunnel?" />
            </div>
          </div>
          <div
            :if={Phoenix.HTML.Form.input_value(@server_form, :ssh_tunnel) == true}
            class="md:col-span-3 p-4 bg-base-200 rounded-lg mb-2"
          >
            <h3 class="font-semibold mb-2">SSH Tunnel Configuration</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="md:col-span-2">
                <.input field={@server_form[:ssh_hostname]} type="text" label="SSH Hostname" />
              </div>
              <.input field={@server_form[:ssh_port]} type="number" label="SSH Port" value={22} />
              <.input field={@server_form[:ssh_username]} type="text" label="SSH Username" />

              <div class="md:col-span-3">
                <.input
                  field={@server_form[:ssh_password_input]}
                  type="password"
                  label="SSH Password"
                  placeholder={password_placeholder(@server_form, :ssh_password)}
                />
                <.input
                  field={@server_form[:ssh_private_key_input]}
                  type="textarea"
                  rows="3"
                  label="SSH Private Key"
                  class="font-mono"
                />
              </div>
              <.input
                field={@server_form[:ssh_key_passphrase]}
                type="password"
                label="Key Passphrase (optional)"
              />
            </div>
          </div>
          <footer class="md:col-span-2">
            <.button phx-disable-with="Connecting..." variant="primary" class="w-full">
              Test Connection
            </.button>
          </footer>
        </.form>
      </section>
      
    <!-- Step 3: Define a Check -->
      <section :if={@server.id} class="mb-12">
        <h2 class="text-2xl font-semibold mb-2">3. Configure a Data Integrity Check</h2>
        <p class="mb-4">
          Write a SQL query that returns a number or boolean. This will be monitored for unexpected values or anomalies.
        </p>
        <.form
          for={@check_form}
          id="check-form"
          phx-change="validate_check"
          phx-submit="save_check"
          class=""
        >
          <div class="mb-4">
            <.input
              field={@check_form[:name]}
              type="text"
              placeholder="Check Name (e.g. Daily User Count)"
              label="Check Name"
              required
            />
          </div>

          <div class="mb-4">
            <label class="font-medium mb-1 block">SQL Query</label>
            <.live_component
              module={QueryCanaryWeb.Components.SQLEditor}
              id="check-sql-editor"
              server={@server}
              input_name={@check_form[:query].name}
              value={@check_form[:query].value}
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <div>
              <label class="font-medium mb-1 block">Schedule</label>
              <.input
                field={@check_form[:schedule]}
                type="text"
                value={@check_form[:schedule].value || "0 8 * * *"}
              />
            </div>

            <div class="text-right">
              <.button phx-disable-with="Running..." variant="success">
                Run Query
              </.button>
            </div>
          </div>
        </.form>
      </section>
      
    <!-- Step 4: Done -->
      <section :if={@check.id}>
        <h2 class="text-2xl font-semibold mb-2">4. You're All Set!</h2>
        <p class="mb-4">
          QueryCanary will now monitor your data and alert you to issues before they escalate.
        </p>
        <.preview_results_table :if={@result} result={@result} />
        <div class="alert alert-info">
          <span>
            📣 Tip: Add Slack or Email notifications in your <a href="#" class="link">alert settings</a>.
          </span>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp preview_results_table(assigns) do
    ~H"""
    <div class="mt-6 bg-base-200 p-4 rounded-lg">
      <h3 class="text-lg font-semibold mb-3">Query Results</h3>

      <%= if Map.has_key?(@result, :error) do %>
        <div class="alert alert-error">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="stroke-current shrink-0 h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span>{@result.error}</span>
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <%= for column <- @result.columns do %>
                  <th>{column}</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @result.rows do %>
                <tr>
                  <%= for {_col, value} <- row do %>
                    <td class="font-mono">{format_cell_value(value)}</td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
            <tfoot :if={length(@result.rows) > 10}>
              <tr>
                <td colspan={length(@result.columns)} class="text-center font-medium">
                  {@result.num_rows} row{if @result.num_rows != 1, do: "s"} returned
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div class="mt-4 bg-base-300 p-3 rounded text-sm">
          <div class="font-semibold">Query Statistics</div>
          <div class="flex flex-wrap gap-4 mt-1">
            <span><strong>Rows:</strong> {@result.num_rows}</span>
            <span><strong>Columns:</strong> {length(@result.columns)}</span>
            <span><strong>Type:</strong> {guess_result_type(@result)}</span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper function to format cell values for display
  defp format_cell_value(nil), do: "<NULL>"
  defp format_cell_value(value) when is_binary(value), do: value
  defp format_cell_value(value) when is_number(value), do: "#{value}"

  defp format_cell_value(value) when is_boolean(value) do
    if value, do: "true", else: "false"
  end

  defp format_cell_value(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_cell_value(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_cell_value(value), do: inspect(value)

  # Helper function to guess the type of result for analytical purposes
  defp guess_result_type(%{rows: rows, num_rows: num_rows}) do
    cond do
      num_rows == 0 -> "Empty result"
      num_rows == 1 && map_size(List.first(rows)) == 1 -> "Single value"
      true -> "Table data"
    end
  end

  @impl true
  def mount(params, _session, socket) do
    server = %Server{user_id: socket.assigns.current_scope.user.id}
    check = %Checks.Check{user_id: socket.assigns.current_scope.user.id}

    {:ok,
     socket
     |> assign(:page_title, "QueryCanary Quickstart")
     |> assign(:engine, nil)
     |> assign(:server, server)
     |> assign(:check, check)
     |> assign(:result, nil)
     |> assign(
       :server_form,
       to_form(Servers.change_server(socket.assigns.current_scope, server))
     )
     |> assign(
       :check_form,
       to_form(Checks.change_check(socket.assigns.current_scope, check))
     )}
  end

  @impl true
  def handle_params(unsigned_params, uri, socket) do
    {:noreply,
     socket
     |> assign(:engine, Map.get(unsigned_params, "engine"))
     |> maybe_assign_server(unsigned_params["server_id"])
     |> maybe_assign_check(unsigned_params["check_id"])}
  end

  defp maybe_assign_server(socket, nil), do: socket

  defp maybe_assign_server(socket, server_id) do
    case get_server(socket.assigns.current_scope, server_id) do
      {:ok, server} ->
        socket
        |> assign(:server, server)
        |> assign(
          :server_form,
          to_form(Servers.change_server(socket.assigns.current_scope, server))
        )

      {:error, :not_found} ->
        put_flash(socket, :error, "Server not found")
    end
  end

  defp get_server(scope, server_id) do
    try do
      {:ok, Servers.get_server!(scope, server_id)}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp maybe_assign_check(socket, nil), do: socket

  defp maybe_assign_check(socket, check_id) do
    case get_check(socket.assigns.current_scope, check_id) do
      {:ok, check} ->
        socket
        |> assign(:check, check)
        |> assign(
          :check_form,
          to_form(Checks.change_check(socket.assigns.current_scope, check))
        )

      {:error, :not_found} ->
        put_flash(socket, :error, "Check not found")
    end
  end

  defp get_check(scope, check_id) do
    try do
      {:ok, Checks.get_check!(scope, check_id)}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  @impl true
  def handle_event("validate_server", %{"server" => server_params}, socket) do
    changeset =
      Servers.change_server(
        socket.assigns.current_scope,
        socket.assigns.server,
        server_params
      )

    {:noreply, assign(socket, server_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_server", %{"server" => server_params}, socket) do
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
        QueryCanary.Connections.ConnectionManager.test_connection(server) |> dbg()

        {:noreply,
         socket
         |> assign(:server, server)
         |> put_flash(:info, "Server created successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, server_form: to_form(changeset))}
    end
  end

  def handle_event("validate_check", %{"check" => check_params}, socket) do
    changeset =
      Checks.change_check(
        socket.assigns.current_scope,
        socket.assigns.check,
        check_params
      )

    {:noreply, assign(socket, check_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_check", %{"check" => check_params}, socket) do
    check =
      if socket.assigns.check.id do
        Checks.update_check(
          socket.assigns.current_scope,
          socket.assigns.check,
          check_params
        )
      else
        check_params = Map.put(check_params, "server_id", socket.assigns.server.id)
        Checks.create_check(socket.assigns.current_scope, check_params)
      end

    case check |> dbg() do
      {:ok, check} ->
        # QueryCanary.Connections.ConnectionManager.test_connection(server) |> dbg()

        case QueryCanary.Connections.ConnectionManager.run_query(
               socket.assigns.server,
               check.query
             ) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:check, check)
             |> assign(:result, result)
             |> put_flash(:info, "Check created successfully")}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:check, check)
             |> assign(:result, %{error: error})
             |> put_flash(:info, "Check errored")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, check_form: to_form(changeset))}
    end
  end

  defp password_placeholder(form, field) do
    if Phoenix.HTML.Form.input_value(form, field) |> dbg() do
      "•••••• previously set ••••••"
    else
      nil
    end
  end
end
