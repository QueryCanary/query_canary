defmodule QueryCanaryWeb.CheckLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Check {@check.id}
        <:subtitle>This is a check record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/checks"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/checks/#{@check}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit check
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Query">{@check.query}</:item>
        <:item title="Expectation">{@check.expectation}</:item>
      </.list>
      
    <!-- Page Header -->
      <div class="flex justify-between items-center">
        <div>
          <h1 class="text-3xl font-bold">User Signup Count Check</h1>
          <p class="text-sm opacity-70">Last run: 2 minutes ago • Every 5 min</p>
        </div>
        <button class="btn btn-outline btn-sm">Edit Check</button>
      </div>
      
    <!-- SQL Query Viewer -->
      <div class="card shadow-lg bg-base-200">
        <div class="card-body">
          <h2 class="card-title text-lg">SQL Query</h2>
          <pre class="bg-base-300 text-sm p-4 rounded-lg overflow-x-auto font-mono">{@check.query}</pre>
        </div>
      </div>
      
    <!-- Result Chart and Summary -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Chart Card -->
        <div class="card bg-base-200 shadow-lg">
          <div class="card-body">
            <h2 class="card-title">Result History</h2>
            <canvas id="resultChart" class="w-full h-64"></canvas>
          </div>
        </div>
        
    <!-- Recent Results -->
        <div class="card bg-base-200 shadow-lg">
          <div class="card-body space-y-2">
            <h2 class="card-title">Recent Runs</h2>
            <ul class="divide-y divide-base-300 text-sm">
              <li class="py-2 flex justify-between">
                <span>2025-05-13 12:30</span>
                <span class="badge badge-success">Pass</span>
                <span class="text-xs opacity-70">42 ms</span>
              </li>
              <li class="py-2 flex justify-between">
                <span>2025-05-13 12:25</span>
                <span class="badge badge-error">Fail</span>
                <span class="text-xs opacity-70">55 ms</span>
              </li>
              <li class="py-2 flex justify-between">
                <span>2025-05-13 12:20</span>
                <span class="badge badge-success">Pass</span>
                <span class="text-xs opacity-70">39 ms</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <script>
        const ctx = document.getElementById("resultChart").getContext("2d");
        new Chart(ctx, {
          type: "line",
          data: {
            labels: ["12:10", "12:15", "12:20", "12:25", "12:30"],
            datasets: [
              {
                label: "Latency (ms)",
                data: [42, 51, 39, 55, 42],
                borderColor: "#5c6ac4",
                backgroundColor: "rgba(92,106,196,0.1)",
                tension: 0.4,
                yAxisID: 'y',
              },
              {
                label: "Success",
                data: [1, 1, 1, 0, 1],
                type: "bar",
                backgroundColor: "#36d399",
                yAxisID: 'y1',
              }
            ],
          },
          options: {
            scales: {
              y: {
                type: 'linear',
                position: 'left',
                title: { display: true, text: 'Latency (ms)' },
              },
              y1: {
                type: 'linear',
                position: 'right',
                min: 0,
                max: 1,
                grid: { drawOnChartArea: false },
                title: { display: true, text: 'Success' },
                ticks: {
                  callback: (val) => (val === 1 ? '✓' : '×')
                }
              }
            },
          },
        });
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Checks.subscribe_checks(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Check")
     |> assign(:check, Checks.get_check!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %QueryCanary.Checks.Check{id: id} = check},
        %{assigns: %{check: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :check, check)}
  end

  def handle_info(
        {:deleted, %QueryCanary.Checks.Check{id: id}},
        %{assigns: %{check: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current check was deleted.")
     |> push_navigate(to: ~p"/checks")}
  end

  def handle_info({type, %QueryCanary.Checks.Check{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
