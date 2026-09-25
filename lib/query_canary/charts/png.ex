defmodule QueryCanary.Charts.PNG do
  @moduledoc "Renders the site's shared Chart.js configuration locally, with bounded execution."

  @timeout 10_000
  @max_output 4_000_000

  def render(data, opts \\ []) do
    executable = Keyword.get(opts, :executable, System.find_executable("node"))
    script = Keyword.get(opts, :script, script_path())

    if is_binary(executable) and File.regular?(script) do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          args: [script]
        ])

      try do
        Port.command(port, [Jason.encode!(data), "\n"])
        deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, @timeout)
        receive_png(port, deadline, [], 0)
      after
        if Port.info(port), do: Port.close(port)
      end
    else
      {:error, :renderer_unavailable}
    end
  rescue
    _ -> {:error, :render_failed}
  end

  defp receive_png(port, deadline, chunks, size) do
    receive do
      {^port, {:data, chunk}} when size + byte_size(chunk) <= @max_output ->
        receive_png(port, deadline, [chunk | chunks], size + byte_size(chunk))

      {^port, {:data, _}} ->
        {:error, :output_too_large}

      {^port, {:exit_status, 0}} ->
        case chunks |> Enum.reverse() |> IO.iodata_to_binary() do
          <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = png -> {:ok, png}
          _ -> {:error, :invalid_image}
        end

      {^port, {:exit_status, _}} ->
        {:error, :render_failed}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :timeout}
    end
  end

  defp script_path do
    Application.get_env(:query_canary, :chart_renderer_script) ||
      Application.app_dir(:query_canary, "priv/chart_renderer/render.cjs")
  end
end
