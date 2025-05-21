defmodule QueryCanaryWeb.CheckAuth do
  import Phoenix.LiveView
  import Phoenix.Component

  alias QueryCanary.Checks

  def on_mount(:default, %{"id" => check_id}, _session, socket) do
    try do
      check = Checks.get_check!(check_id)

      if Checks.can_perform?(:view, socket.assigns.current_scope, check) do
        {:cont, assign(socket, :check, check)}
      else
        {:halt,
         socket
         |> put_flash(:error, "You don't have permission to access this check!")
         |> redirect(to: "/")}
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
