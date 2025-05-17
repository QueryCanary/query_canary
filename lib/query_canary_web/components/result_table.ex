defmodule QueryCanaryWeb.ResultTable do
  use Phoenix.Component

  attr :columns, :list
  attr :rows, :list
  attr :error, :string, default: nil

  def preview_results_table(assigns) do
    ~H"""
    <div class="mt-6 bg-base-200 p-4 rounded-lg">
      <h3 class="text-lg font-semibold mb-3">Query Results</h3>

      <%= if @error do %>
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
          <span>{@error}</span>
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <%= for column <- @columns do %>
                  <th>{column}</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @rows do %>
                <tr>
                  <%= for {_col, value} <- row do %>
                    <td class="font-mono">{format_cell_value(value)}</td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
            <tfoot :if={length(@rows) > 10}>
              <tr>
                <td colspan={length(@columns)} class="text-center font-medium">
                  {length(@rows)} row{if length(@rows) != 1, do: "s"} returned
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
