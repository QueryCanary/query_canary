defmodule QueryCanaryWeb.RedirectController do
  use QueryCanaryWeb, :controller

  def docs(conn, _params), do: redirect(conn, to: "/docs/overview")
end
