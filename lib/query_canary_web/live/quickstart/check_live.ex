defmodule QueryCanaryWeb.Quickstart.CheckLive do
  alias Crontab.CronExpression
  alias DBConnection.Query
  use QueryCanaryWeb, :live_view

  import Crontab.CronExpression

  alias QueryCanary.Servers
  alias QueryCanary.Checks
  alias QueryCanary.Checks.Check

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-3xl font-bold mb-6">QueryCanary Quickstart</h1>

      <section>
        <h2 class="text-2xl font-semibold mb-2">2. Configure a Data Integrity Check</h2>
        <p class="mb-4">
          Write a SQL query that returns a number or boolean. This will be monitored for unexpected values or anomalies.
        </p>
        <.form for={@form} id="check-form" phx-change="validate" phx-submit="save" class="">
          <div class="mb-4">
            <.input
              field={@form[:name]}
              type="text"
              placeholder="Check Name (e.g. Daily User Count)"
              label="Check Name"
              required
              autofocus
            />
          </div>

          <div class="mb-4">
            <label class="font-medium mb-1 block">SQL Query</label>
            <.live_component
              module={QueryCanaryWeb.Components.SQLEditor}
              id="check-sql-editor"
              server={@server}
              input_name={@form[:query].name}
              value={@form[:query].value}
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4 items-center">
            <div>
              <label class="font-medium mb-1 block">Schedule</label>
              <.input
                field={@form[:schedule]}
                type="text"
                value={@form[:schedule].value || "0 8 * * *"}
              />
            </div>

            <div class="text-right">
              <label class="font-medium mb-1 block">Next Runs for Schedule</label>
              <ul>
                <li :for={d <- @next_schedule} class="text-sm">
                  {Calendar.strftime(d, "%Y-%m-%d %H:%M:%S")}
                </li>
              </ul>
            </div>
          </div>
          <div>
            <.button phx-disable-with="Running..." variant="success">
              Run Query & Preview Results
            </.button>
          </div>
        </.form>
      </section>

      <section :if={@result}>
        <h2 class="text-2xl font-semibold mb-2">3. You're All Set!</h2>
        <p class="mb-4">
          QueryCanary will now monitor your data and alert you to issues before they escalate.
        </p>
        <.preview_results_table result={@result} />
        <.button navigate={~p"/checks/#{@check}"} variant="info">Go to Check</.button>
      </section>
    </Layouts.app>
    """
  end

  def mount(%{"server_id" => server_id}, _session, socket) do
    server = Servers.get_server!(socket.assigns.current_scope, server_id)
    check = %Check{user_id: socket.assigns.current_scope.user.id, server_id: server.id}

    # CronExpression.Parser.parse!("0 8 * * *")

    {:ok,
     socket
     |> assign(:server, server)
     |> assign(:check, check)
     |> assign(:result, nil)
     |> assign(
       :next_schedule,
       Enum.take(Crontab.Scheduler.get_next_run_dates(~e[0 8 * * *]), 3)
     )
     |> assign(
       :form,
       to_form(Checks.change_check(socket.assigns.current_scope, check))
     )}
  end

  def handle_params(%{"check_id" => check_id, "server_id" => _}, _uri, socket) do
    case Checks.get_check(socket.assigns.current_scope, check_id) do
      %Check{} = check ->
        {:noreply,
         socket
         |> assign(:check, check)
         |> assign(
           :form,
           to_form(Checks.change_check(socket.assigns.current_scope, check))
         )}

      nil ->
        {:noreply,
         socket
         |> push_patch(to: ~p"/quickstart/check")
         |> put_flash(:error, "Check not found")}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"check" => check_params}, socket) do
    changeset =
      Checks.change_check(
        socket.assigns.current_scope,
        socket.assigns.check,
        check_params
      )

    {:noreply,
     socket
     |> maybe_put_next_schedule(changeset)
     |> assign(form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"check" => check_params}, socket) do
    current_scope = socket.assigns.current_scope

    check =
      if socket.assigns.check.id do
        Checks.update_check(
          current_scope,
          socket.assigns.check,
          check_params
        )
      else
        check_params = Map.put(check_params, "server_id", socket.assigns.server.id)
        Checks.create_check(current_scope, check_params)
      end

    case check do
      {:ok, check} ->
        case QueryCanary.Connections.ConnectionManager.run_query(
               socket.assigns.server,
               check.query
             ) do
          {:ok, result} ->
            {:ok, check} = Checks.update_check(current_scope, check, %{enabled: true})

            {:noreply,
             socket
             |> assign(:check, check)
             |> assign(:result, result)
             |> push_patch(
               to:
                 ~p"/quickstart/check?server_id=#{socket.assigns.server.id}&check_id=#{check.id}"
             )
             |> put_flash(:info, "Check ran successfully")}

          {:error, error} ->
            {:noreply,
             socket
             |> assign(:check, check)
             |> assign(:result, %{error: error})
             |> put_flash(:info, "Check errored")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def maybe_put_next_schedule(socket, changeset) do
    schedule = Ecto.Changeset.get_change(changeset, :schedule)

    try do
      next_schedule =
        case CronExpression.Parser.parse(schedule || "") do
          {:ok, exp} -> Enum.take(Crontab.Scheduler.get_next_run_dates(exp), 3)
          _ -> socket.assigns.next_schedule
        end

      socket |> assign(:next_schedule, next_schedule)
    catch
      e ->
        socket.assigns.next_schedule
    end
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
end
