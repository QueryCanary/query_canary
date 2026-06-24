defmodule QueryCanaryWeb.MetricLive.Index do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics

  def mount(_params, _session, socket) do
    {:ok, assign(socket, metrics: Metrics.list_metrics())}
  end

  def render(assigns) do
    ~H"""
    <.header>
      Metrics
      <:actions>
        <.link navigate="/metrics/new" class="btn btn-primary">New Metric</.link>
      </:actions>
    </.header>

    <div class="overflow-x-auto">
      <table class="table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Granularity</th>
            <th>Server</th>
            <th>Enabled</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for m <- @metrics do %>
            <tr>
              <td><.link navigate={"/metrics/#{m.id}"} class="link">{m.name}</.link></td>
              <td>{m.granularity}</td>
              <td>{m.server_id}</td>
              <td>{if m.enabled, do: "Yes", else: "No"}</td>
              <td class="text-right">
                <.link navigate={"/metrics/#{m.id}/edit"} class="btn btn-ghost btn-sm">Edit</.link>
                <.link navigate={"/metrics/#{m.id}/backfill"} class="btn btn-ghost btn-sm">
                  Backfill
                </.link>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end
end
