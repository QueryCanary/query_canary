defmodule QueryCanaryWeb.MetricLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics
  alias QueryCanary.Metrics.Metric
  alias QueryCanary.Servers

  def mount(params, _session, socket) do
    metric = metric_from_params(params)
    servers = Servers.list_servers(socket.assigns.current_scope)

    changeset =
      case metric do
        %Metric{} -> Metric.changeset(metric, %{})
        nil -> Metric.changeset(%Metric{}, %{})
      end

    {:ok, assign(socket, metric: metric, servers: servers, changeset: changeset)}
  end

  def handle_event("validate", %{"metric" => params}, socket) do
    changeset =
      (socket.assigns.metric || %Metric{})
      |> Metric.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"metric" => params}, socket) do
    case save_metric(socket.assigns.metric, params) do
      {:ok, metric} ->
        {:noreply, push_navigate(socket, to: "/metrics/#{metric.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def render(assigns) do
    ~H"""
    <.header>{if @metric, do: "Edit Metric", else: "New Metric"}</.header>

    <.form for={@changeset} as={:metric} phx-change="validate" phx-submit="save">
      <.input name="metric[name]" value={@changeset.data.name} label="Name" />
      <.input name="metric[sql]" type="textarea" value={@changeset.data.sql} label="SQL" rows="6" />
      <.input
        name="metric[granularity]"
        type="select"
        value={@changeset.data.granularity}
        label="Base Granularity"
        options={["minute", "hour", "day", "week", "month"]}
      />
      <p class="mb-2 text-xs text-base-content/70">
        Metrics run automatically at `0 8 * * *`.
      </p>
      <.input name="metric[timezone]" value={@changeset.data.timezone} label="Timezone" />
      <.input name="metric[enabled]" type="checkbox" value={@changeset.data.enabled} label="Enabled" />
      <.input
        name="metric[server_id]"
        type="select"
        label="Server"
        options={for s <- @servers, do: {s.name, s.id}}
        value={@changeset.data.server_id}
      />

      <div class="mt-4">
        <.button type="submit">Save</.button>
      </div>
    </.form>
    """
  end

  defp metric_from_params(%{"id" => id}) do
    Metrics.get_metric!(id)
  rescue
    _ -> nil
  end

  defp metric_from_params(_), do: nil

  defp save_metric(nil, params) do
    Metrics.create_metric(params)
  end

  defp save_metric(%Metric{} = metric, params) do
    Metrics.update_metric(metric, params)
  end
end
