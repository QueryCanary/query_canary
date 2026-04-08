defmodule QueryCanaryWeb.MetricLive.Show do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics

  def mount(%{"id" => id}, _session, socket) do
    metric = Metrics.get_metric!(id)
    {:ok, assign(socket, metric: metric, results: load_results(metric))}
  end

  def handle_event("refresh", _, socket) do
    {:noreply, assign(socket, results: load_results(socket.assigns.metric))}
  end

  def render(assigns) do
    ~H"""
    <.header>
      {@metric.name}
      <:subtitle>
        <span class="badge">{@metric.granularity}</span>
      </:subtitle>
      <:actions>
        <.link navigate={"/metrics/#{@metric.id}/edit"} class="btn">Edit</.link>
        <.link navigate={"/metrics/#{@metric.id}/backfill"} class="btn btn-ghost">Backfill</.link>
        <button phx-click="refresh" class="btn btn-ghost">Refresh</button>
      </:actions>
    </.header>

    <div class="overflow-x-auto">
      <table class="table">
        <thead>
          <tr>
            <th>From</th>
            <th>To</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          <%= for r <- @results do %>
            <tr>
              <td>{r.from_ts}</td>
              <td>{r.to_ts}</td>
              <td>{r.value}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp load_results(metric) do
    Metrics.list_metric_results(metric, limit: 200)
  end
end
