defmodule QueryCanaryWeb.CheckAuth do
  import Phoenix.LiveView
  import Phoenix.Component

  alias QueryCanary.Checks

  def on_mount(:view, %{"id" => check_id}, _session, socket) do
    with %QueryCanary.Checks.Check{} = check <- Checks.get_possibly_public_check(check_id),
         true <- Checks.can_perform?(:view, socket.assigns.current_scope, check) do
      {:cont, assign(socket, :check, check)}
    else
      _ ->
        {:halt,
         socket
         |> put_flash(:error, "You don't have permission to access this check!")
         |> redirect(to: "/")}
    end
  end

  def on_mount(:edit, %{"id" => check_id}, _session, socket) do
    with %QueryCanary.Checks.Check{} = check <- Checks.get_possibly_public_check(check_id),
         true <- Checks.can_perform?(:edit, socket.assigns.current_scope, check) do
      {:cont, assign(socket, :check, check)}
    else
      _ ->
        {:halt,
         socket
         |> put_flash(:error, "You don't have permission to access this check!")
         |> redirect(to: "/")}
    end
  end
end
