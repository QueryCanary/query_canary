defmodule QueryCanaryWeb.PageController do
  use QueryCanaryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
