defmodule QueryCanaryWeb.MetricLive.Backfill do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Metrics
  import Ecto.Changeset

  def mount(%{"id" => id}, _session, socket) do
    metric = Metrics.get_metric!(id)

    {:ok,
     socket
     |> assign(:metric, metric)
     |> assign(:changeset, backfill_changeset(%{}))}
  end

  def handle_event("validate", %{"backfill" => params}, socket) do
    {:noreply,
     assign(socket, :changeset, backfill_changeset(params) |> Map.put(:action, :validate))}
  end

  def handle_event("submit", %{"backfill" => params}, %{assigns: %{metric: metric}} = socket) do
    changeset = backfill_changeset(params)

    if changeset.valid? do
      %{:start_date => s, :end_date => e} = changeset.changes
      {:ok, _job} = Metrics.enqueue_backfill(metric.id, s, e)

      {:noreply,
       socket
       |> put_flash(:info, "Backfill enqueued for #{metric.name}")
       |> push_navigate(to: "/metrics/#{metric.id}")}
    else
      {:noreply, assign(socket, :changeset, Map.put(changeset, :action, :insert))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-2xl">
      <.header>
        Backfill {@metric.name}
        <:subtitle>
          Granularity: {@metric.granularity} • Timezone: {@metric.timezone || "Etc/UTC"}
        </:subtitle>
      </.header>

      <.form
        for={@changeset}
        id="backfill-form"
        phx-change="validate"
        phx-submit="submit"
        as={:changeset}
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input
            type="date"
            name="backfill[start_date]"
            label="Start date"
            value={Phoenix.HTML.Form.input_value(:changeset, :start_date)}
          />
          <.input
            type="date"
            name="backfill[end_date]"
            label="End date"
            value={Phoenix.HTML.Form.input_value(:changeset, :end_date)}
          />
        </div>

        <div class="mt-4 flex items-center gap-2">
          <.button type="submit">Enqueue Backfill</.button>
          <.link navigate={"/metrics/#{@metric.id}"} class="text-sm opacity-70 hover:underline">
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp backfill_changeset(params) do
    types = %{start_date: :date, end_date: :date}

    {%{}, types}
    |> cast(params, Map.keys(types))
    |> validate_required([:start_date, :end_date])
    |> validate_change(:end_date, fn :end_date, to ->
      case params do
        %{"start_date" => s} when is_binary(s) and s != "" ->
          case Date.from_iso8601(s) do
            {:ok, from} ->
              if Date.compare(to, from) in [:gt, :eq],
                do: [],
                else: [end_date: "must be on or after start date"]

            _ ->
              []
          end

        _ ->
          []
      end
    end)
  end
end
