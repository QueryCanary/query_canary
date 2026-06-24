defmodule QueryCanaryWeb.ReportLive.NewMetricComponent do
  use QueryCanaryWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="new-metric-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-metric-title"
      phx-window-keydown="cancel_create_metric"
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-base-content/45 backdrop-blur-sm"
        phx-click="cancel_create_metric"
      >
      </div>

      <div class="relative z-10 w-full max-w-3xl overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-2xl">
        <div class="flex items-start justify-between gap-4 border-b border-base-200 px-6 py-5">
          <div class="space-y-2">
            <div class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
              New Metric
            </div>
            <h3 id="new-metric-title" class="text-2xl font-semibold tracking-tight">
              Create metric in {@creating_group.name}
            </h3>
            <p class="text-sm text-base-content/60">
              Save a new metric and add it directly to this report group.
            </p>
          </div>

          <button
            id="close-new-metric-modal"
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click="cancel_create_metric"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </button>
        </div>

        <div class="max-h-[80vh] overflow-y-auto px-6 py-5">
          <.form
            id={"new-metric-form-#{@creating_group.id}"}
            for={@new_metric_form}
            phx-change="validate_new_metric"
            phx-submit="create_metric_for_group"
            class="space-y-3"
          >
            <input type="hidden" name="group_id" value={@creating_group.id} />
            <div class="grid gap-3 md:grid-cols-2">
              <.input field={@new_metric_form[:name]} label="Name" />
              <.input
                field={@new_metric_form[:server_id]}
                type="select"
                label="Server"
                options={server_options(@servers)}
              />
            </div>
            <.input
              field={@new_metric_form[:description]}
              type="textarea"
              label="Description"
              rows="2"
            />
            <.input field={@new_metric_form[:sql]} type="textarea" label="SQL" rows="6" />
            <div class="grid gap-3 md:grid-cols-3">
              <.input
                field={@new_metric_form[:granularity]}
                type="select"
                label="Base Granularity"
                options={granularity_options()}
              />
              <.input field={@new_metric_form[:timezone]} label="Timezone" />
            </div>
            <p class="text-xs text-base-content/70">
              Metrics run automatically at `0 8 * * *`.
            </p>
            <.input field={@new_metric_form[:enabled]} type="checkbox" label="Enabled" />

            <div class="flex items-center gap-2 pt-2">
              <.button type="submit" variant="primary-sm">Create metric</.button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_create_metric">
                Cancel
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp granularity_options, do: ["minute", "hour", "day", "week", "month"]

  defp server_options(servers) do
    Enum.map(servers, fn server -> {server.name, server.id} end)
  end
end
