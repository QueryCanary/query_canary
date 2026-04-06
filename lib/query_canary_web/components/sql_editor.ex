defmodule QueryCanaryWeb.Components.SQLEditor do
  use Phoenix.LiveComponent
  import Phoenix.HTML

  attr :id, :string, default: nil
  attr :value, :string, default: ""
  attr :input_name, :string, default: nil
  attr :server, :map, required: true
  attr :read_only, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div id={@id} class="w-full" phx-update="ignore">
      <div
        id={"#{@id}-editor"}
        phx-hook="SQLEditor"
        data-server-id={@server.id}
        data-dialect={@server.db_engine || "postgres"}
        data-read-only={to_string(@read_only)}
        class="min-h-56 border rounded-md overflow-hidden bg-base-100"
      >
      </div>

      <script id={"#{@id}-schema"} type="application/json">
        <%= raw(JSON.encode!(@server.schema || %{})) %>
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
     |> assign(:input_name, assigns[:input_name])
     |> assign(:server, assigns[:server])}
  end
end
