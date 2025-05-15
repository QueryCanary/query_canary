defmodule QueryCanaryWeb.Components.SQLEditor do
  use Phoenix.LiveComponent
  import Phoenix.HTML

  alias QueryCanary.Connections.SQLSchemaProvider

  def render(assigns) do
    ~H"""
    <div id={@id} class="w-full" phx-update="ignore">
      <div
        id={"#{@id}-editor"}
        phx-hook="SQLEditor"
        data-server-id={@server.id}
        data-dialect={@server.db_engine || "postgres"}
        class="border rounded-md overflow-hidden"
      >
      </div>

      <script id={"#{@id}-schema"} type="application/json">
        <%= raw(SQLSchemaProvider.get_schema_js(@server)) %>
      </script>

      <input type="hidden" name={@input_name} id={"#{@id}-input"} value={@value} />
    </div>
    """
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:id, assigns[:id] || "sql-editor-#{:erlang.monotonic_time()}")
     |> assign(:value, assigns[:value] || "")
     |> assign(:input_name, assigns[:input_name] || "query")
     |> assign(:server, assigns[:server])}
  end
end
