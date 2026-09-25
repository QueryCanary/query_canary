defmodule Mix.Tasks.Assets.ChartRenderer do
  use Mix.Task

  @shortdoc "Packages the shared Chart.js renderer and its native canvas for releases"
  def run(_) do
    Mix.Task.run("esbuild", ["chart_renderer"])

    # Keep native dependencies outside the bundle, in the release's private assets.
    source = Path.expand("assets/node_modules/@napi-rs")
    target = Path.expand("priv/chart_renderer/node_modules/@napi-rs")
    File.mkdir_p!(Path.dirname(target))
    File.cp_r!(source, target)
  end
end
