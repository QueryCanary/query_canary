defmodule QueryCanaryWeb.CheckLive.Form do
  use QueryCanaryWeb, :live_view

  alias QueryCanary.Checks
  alias QueryCanary.Checks.Check

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage check records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="check-form" phx-change="validate" phx-submit="save">
        <.live_component
          module={QueryCanaryWeb.Components.SQLEditor}
          id="check-sql-editor"
          server={@check.server}
          input_name={@form[:query].name}
          value={@form[:query].value}
        />
        <.input field={@form[:expectation]} type="text" label="Expectation" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Check</.button>
          <.button navigate={return_path(@current_scope, @return_to, @check)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    check = Checks.get_check!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Check")
    |> assign(:check, check)
    |> assign(:form, to_form(Checks.change_check(socket.assigns.current_scope, check)))
  end

  defp apply_action(socket, :new, _params) do
    check = %Check{user_id: socket.assigns.current_scope.user.id}

    socket
    |> assign(:page_title, "New Check")
    |> assign(:check, check)
    |> assign(:form, to_form(Checks.change_check(socket.assigns.current_scope, check)))
  end

  @impl true
  def handle_event("validate", %{"check" => check_params}, socket) do
    changeset =
      Checks.change_check(socket.assigns.current_scope, socket.assigns.check, check_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"check" => check_params}, socket) do
    save_check(socket, socket.assigns.live_action, check_params)
  end

  defp save_check(socket, :edit, check_params) do
    case Checks.update_check(socket.assigns.current_scope, socket.assigns.check, check_params) do
      {:ok, check} ->
        {:noreply,
         socket
         |> put_flash(:info, "Check updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, check)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_check(socket, :new, check_params) do
    case Checks.create_check(socket.assigns.current_scope, check_params) do
      {:ok, check} ->
        {:noreply,
         socket
         |> put_flash(:info, "Check created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_scope, socket.assigns.return_to, check)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _check), do: ~p"/checks"
  defp return_path(_scope, "show", check), do: ~p"/checks/#{check}"
end
