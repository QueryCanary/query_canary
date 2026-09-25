defmodule QueryCanaryWeb.ScheduleForm do
  @moduledoc false

  alias QueryCanary.Checks.Schedule

  def initial_ui(check), do: Schedule.from_cron(check.schedule)

  def prepare(check_params, ui_params, current_ui, current_cron) do
    ui_params = ui_params || %{}
    ui = Map.merge(current_ui, Map.take(ui_params, ~w(kind time weekday monthday)))
    raw_cron = Map.get(check_params, "schedule", current_cron)

    cond do
      ui != current_ui and ui["kind"] != "custom" ->
        case Schedule.to_cron(ui) do
          {:ok, cron} -> {Map.put(check_params, "schedule", cron), ui, nil}
          {:error, error} -> {Map.put(check_params, "schedule", ""), ui, error}
        end

      ui != current_ui and ui["kind"] == "custom" ->
        {Map.put(check_params, "schedule", raw_cron), ui, nil}

      raw_cron != current_cron ->
        next_ui = if ui["kind"] == "custom", do: ui, else: Schedule.from_cron(raw_cron)
        {check_params, next_ui, nil}

      true ->
        {check_params, ui, nil}
    end
  end

  def add_schedule_error(changeset, nil), do: changeset

  def add_schedule_error(changeset, error) do
    Ecto.Changeset.add_error(changeset, :schedule, error)
  end

  def next_runs(changeset) do
    cron = Ecto.Changeset.get_field(changeset, :schedule)
    timezone = Ecto.Changeset.get_field(changeset, :timezone)
    Schedule.next_runs(cron || "", timezone || "Etc/UTC")
  end
end
