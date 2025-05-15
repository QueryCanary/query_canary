defmodule QueryCanaryWeb.CheckLive.Index do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Checks
        <:actions>
          <.button variant="primary" navigate={~p"/checks/new"}>
            <.icon name="hero-plus" /> New Check
          </.button>
        </:actions>
      </.header>

      <.table
        id="checks"
        rows={@streams.checks}
        row_click={fn {_id, check} -> JS.navigate(~p"/checks/#{check}") end}
      >
        <:col :let={{_id, check}} label="Query">{check.query}</:col>
        <:col :let={{_id, check}} label="Expectation">{check.expectation}</:col>
        <:action :let={{_id, check}}>
          <div class="sr-only">
            <.link navigate={~p"/checks/#{check}"}>Show</.link>
          </div>
          <.link navigate={~p"/checks/#{check}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, check}}>
          <.link
            phx-click={JS.push("delete", value: %{id: check.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Checks.subscribe_checks(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Checks")
     |> stream(:checks, Checks.list_checks(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    check = Checks.get_check!(socket.assigns.current_scope, id)
    {:ok, _} = Checks.delete_check(socket.assigns.current_scope, check)

    {:noreply, stream_delete(socket, :checks, check)}
  end

  @impl true
  def handle_info({type, %QueryCanary.Checks.Check{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, stream(socket, :checks, Checks.list_checks(socket.assigns.current_scope), reset: true)}
  end
end
