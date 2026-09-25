defmodule QueryCanaryWeb.NotificationComponents do
  use QueryCanaryWeb, :html
  alias QueryCanary.Notifications

  def settings(scope, server, fetch_channels?) do
    integrations = Notifications.list_integrations(scope, server.team_id)

    Enum.map(integrations, fn integration ->
      channels =
        if fetch_channels?,
          do: Notifications.list_channels(scope, server.team_id, integration.provider),
          else: {:ok, []}

      case channels do
        {:ok, channels} -> Map.merge(integration, %{channels: channels, error: false})
        {:error, _} -> Map.merge(integration, %{channels: [], error: true})
      end
    end)
  end

  attr :form, :any, required: true
  attr :settings, :list, required: true
  attr :team_id, :any, required: true
  attr :email_destination, :string, required: true

  def notification_fields(assigns) do
    ~H"""
    <fieldset id="check-notifications" class="my-6 space-y-3">
      <legend class="text-lg font-semibold">Alert notifications</legend>
      <p class="text-sm text-base-content/60">Choose where this check sends alerts.</p>
      <div class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
        <div class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-3 p-4 sm:grid-cols-[10rem_minmax(0,1fr)_auto]">
          <div class="col-span-2 flex items-center gap-3 sm:col-span-1">
            <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-base-200">
              <.icon name="hero-envelope" class="size-5 text-base-content/60" />
            </span>
            <span class="text-sm font-medium">Email</span>
          </div>
          <p id="check-email-destination" class="min-w-0 break-words text-sm text-base-content/70">
            {@email_destination}
          </p>
          <.notification_toggle form={@form} provider="email" describedby="check-email-destination" />
        </div>
        <div :for={integration <- @settings} class="space-y-3 p-4">
          <div class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-3 sm:grid-cols-[10rem_minmax(0,1fr)_auto]">
            <div class="col-span-2 flex min-w-0 items-center gap-3 sm:col-span-1">
              <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-base-200">
                <.icon name="hero-chat-bubble-left-right" class="size-5 text-base-content/60" />
              </span>
              <div class="min-w-0">
                <p class="text-sm font-medium">{String.capitalize(integration.provider)}</p>
                <p class="truncate text-xs text-base-content/50" title={integration.name}>
                  {integration.name}
                </p>
              </div>
            </div>
            <div class="min-w-0 [&>fieldset]:mb-0">
              <.input
                field={@form[:notification_channels]}
                id={"check-#{integration.provider}-channel"}
                name={"check[notification_channels][#{integration.provider}]"}
                value={selected_channel(@form, integration.provider)}
                type="select"
                aria-label={"#{String.capitalize(integration.provider)} channel"}
                options={channel_options(integration, selected_channel(@form, integration.provider))}
              />
            </div>
            <.notification_toggle form={@form} provider={integration.provider} />
          </div>
          <p :if={integration.error} class="text-sm text-warning" role="status">
            Channels could not be loaded. Your saved channel is still selected. Reload to try again,
            or ask a team admin to reconnect {String.capitalize(integration.provider)}.
          </p>
          <p :if={integration.provider == "slack"} class="text-xs text-base-content/50">
            Missing a channel? Invite the QueryCanary bot to it, then reload.
          </p>
        </div>
      </div>
      <p class="text-xs text-base-content/50">
        Turning notifications off keeps your check running and your channel saved.
      </p>
      <p :if={@settings == [] && @team_id} class="text-sm">
        A team admin can connect Slack in <.link navigate={~p"/teams/#{@team_id}"} class="link">team settings</.link>.
      </p>
      <p :if={is_nil(@team_id)} class="text-sm opacity-70">
        Slack alerts are available for checks on team-owned servers.
      </p>
    </fieldset>
    """
  end

  attr :form, :any, required: true
  attr :provider, :string, required: true
  attr :describedby, :string, default: nil

  defp notification_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-3 [&>fieldset]:mb-0">
      <span class="text-xs text-base-content/50" aria-hidden="true">
        {if notification_enabled?(@form, @provider), do: "On", else: "Off"}
      </span>
      <.input
        field={@form[:notification_preferences]}
        id={"check-#{@provider}-notifications"}
        name={"check[notification_preferences][#{@provider}]"}
        type="checkbox"
        role="switch"
        class="toggle toggle-primary toggle-sm"
        checked={notification_enabled?(@form, @provider)}
        aria-checked={to_string(notification_enabled?(@form, @provider))}
        aria-label={"#{String.capitalize(@provider)} notifications"}
        aria-describedby={@describedby}
      />
    </div>
    """
  end

  defp selected_channel(form, provider),
    do: Map.get(form[:notification_channels].value || %{}, provider, "")

  defp notification_enabled?(form, provider),
    do: Map.get(form[:notification_preferences].value || %{}, provider, true) in [true, "true"]

  defp channel_options(integration, selected) do
    options = Enum.map(integration.channels, &{"##{&1.name}", &1.id})

    options =
      if selected not in [nil, ""] and not Enum.any?(options, &(elem(&1, 1) == selected)),
        do: [{"Saved channel (#{selected})", selected} | options],
        else: options

    [{"No channel selected", ""} | options]
  end
end
