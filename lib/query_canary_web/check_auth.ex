defmodule QueryCanaryWeb.CheckAuth do
  import Phoenix.LiveView
  import Phoenix.Component

  alias QueryCanary.Checks

  def on_mount(:default, %{"id" => check_id}, _session, socket) do
    try do
      if socket.assigns.current_scope do
        {:cont, assign(socket, :check, Checks.get_check!(socket.assigns.current_scope, check_id))}
      else
        {:cont,
         socket
         |> assign(:check, Checks.get_public_check!(check_id))}
      end
    rescue
      Ecto.NoResultsError ->
        {:halt,
         socket
         |> put_flash(:error, "You don't have permission to access this check!")
         |> redirect(to: "/")}
    end
  end
end
