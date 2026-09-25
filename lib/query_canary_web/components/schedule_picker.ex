defmodule QueryCanaryWeb.Components.SchedulePicker do
  use Phoenix.Component

  alias QueryCanary.Checks.Schedule
  import QueryCanaryWeb.CoreComponents, only: [input: 1]

  attr :form, :any, required: true
  attr :ui, :map, required: true
  attr :next_runs, :list, required: true
  attr :auto_timezone, :boolean, default: false

  def schedule_picker(assigns) do
    assigns =
      assigns
      |> assign(:options, Schedule.options())
      |> assign(:weekdays, Schedule.weekdays())
      |> assign(:monthdays, Schedule.monthdays())
      |> assign(:timezones, Tzdata.zone_list() |> Enum.sort())

    ~H"""
    <section
      id="schedule-picker"
      phx-hook="ScheduleTimezone"
      data-auto-timezone={@auto_timezone}
      class="rounded-box border border-base-300 bg-base-200/50 p-5 space-y-4"
    >
      <div>
        <h2 class="font-semibold text-lg">When should this check run?</h2>
        <p class="text-sm text-base-content/70">
          Choose a common schedule or use cron for more control.
        </p>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label for="schedule-kind" class="label">Frequency</label>
          <select
            id="schedule-kind"
            name="schedule_ui[kind]"
            class="select w-full"
            value={@ui["kind"]}
          >
            <option :for={{label, value} <- @options} value={value} selected={@ui["kind"] == value}>
              {label}
            </option>
          </select>
        </div>

        <div :if={@ui["kind"] in ~w(daily weekdays weekly monthly)}>
          <label for="schedule-time" class="label">Time</label>
          <input
            id="schedule-time"
            name="schedule_ui[time]"
            type="time"
            class="input w-full"
            value={@ui["time"]}
            required
          />
        </div>

        <div :if={@ui["kind"] == "weekly"}>
          <label for="schedule-weekday" class="label">Day of week</label>
          <select id="schedule-weekday" name="schedule_ui[weekday]" class="select w-full">
            <option
              :for={{label, value} <- @weekdays}
              value={value}
              selected={@ui["weekday"] == to_string(value)}
            >
              {label}
            </option>
          </select>
        </div>

        <div :if={@ui["kind"] == "monthly"}>
          <label for="schedule-monthday" class="label">Day of month</label>
          <select id="schedule-monthday" name="schedule_ui[monthday]" class="select w-full">
            <option
              :for={{label, value} <- @monthdays}
              value={value}
              selected={@ui["monthday"] == to_string(value)}
            >
              {label}
            </option>
          </select>
          <p class="text-xs text-base-content/60 mt-1">Choose 1–28 so the check runs every month.</p>
        </div>
      </div>

      <div :if={@ui["kind"] == "custom"}>
        <.input field={@form[:schedule]} type="text" label="Cron expression" placeholder="0 8 * * *" />
        <p class="text-xs text-base-content/70 mt-1">Five fields: minute hour day month weekday.</p>
      </div>
      <.input :if={@ui["kind"] != "custom"} field={@form[:schedule]} type="hidden" />
      <p
        :for={error <- if(@ui["kind"] != "custom", do: @form[:schedule].errors, else: [])}
        class="text-error text-sm"
      >
        {elem(error, 0)}
      </p>

      <div>
        <label for="check-timezone" class="label">Time zone</label>
        <select
          id="check-timezone"
          name={@form[:timezone].name}
          class="select w-full"
          data-timezone-select
        >
          <option :for={zone <- @timezones} value={zone} selected={@form[:timezone].value == zone}>
            {zone}
          </option>
        </select>
        <p :for={error <- @form[:timezone].errors} class="text-error text-sm mt-1">
          {elem(error, 0)}
        </p>
      </div>

      <div class="rounded-box bg-base-100 p-4" aria-live="polite">
        <p class="font-medium">
          {Schedule.description(
            @form[:schedule].value || "0 8 * * *",
            @form[:timezone].value || "Etc/UTC"
          )}
        </p>
        <div class="text-sm text-base-content/70 mt-2">
          <p class="font-medium">Next three runs</p>
          <ol :if={@next_runs != []} class="list-decimal list-inside mt-1">
            <li :for={run <- @next_runs}>
              {Calendar.strftime(run, "%a, %b %-d, %Y at %-I:%M %p %Z")}
            </li>
          </ol>
          <p :if={@next_runs == []} class="mt-1">
            Enter a valid schedule and time zone to see upcoming runs.
          </p>
        </div>
      </div>
      <p class="text-xs text-base-content/60">
        At a daylight saving change, a skipped clock time does not run. A repeated daily, weekday, weekly, or monthly time runs once.
      </p>
    </section>
    """
  end
end
