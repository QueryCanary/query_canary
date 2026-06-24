defmodule QueryCanary.Reports do
  @moduledoc """
  Context for configurable metric reports with user/team ownership.
  """

  import Ecto.Query, warn: false

  alias QueryCanary.Accounts.{Scope, TeamUser}
  alias QueryCanary.Metrics.{Metric, MetricResult}
  alias QueryCanary.Repo
  alias QueryCanary.Reports.{AccessError, Report, ReportGroup, ReportGroupMetric}

  ## Listing / fetching

  def list_reports(%Scope{} = scope, opts \\ []) do
    preload = Keyword.get(opts, :preload, default_preload())

    Report
    |> accessible_by_scope(scope.user.id)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def get_report!(%Scope{} = scope, id, opts \\ []) do
    preload = Keyword.get(opts, :preload, default_preload())

    Report
    |> accessible_by_scope(scope.user.id)
    |> where([r, _tu], r.id == ^id)
    |> Repo.one!()
    |> Repo.preload(preload)
  end

  def get_report(%Scope{} = scope, id, opts \\ []) do
    preload = Keyword.get(opts, :preload, default_preload())

    Report
    |> accessible_by_scope(scope.user.id)
    |> where([r, _tu], r.id == ^id)
    |> Repo.one()
    |> case do
      nil -> nil
      report -> Repo.preload(report, preload)
    end
  end

  ## Report CRUD

  def create_report(%Scope{} = scope, attrs) do
    with {:ok, report} <-
           %Report{}
           |> Report.changeset(attrs, scope)
           |> Repo.insert() do
      {:ok, Repo.preload(report, default_preload())}
    end
  end

  def update_report(%Scope{} = scope, %Report{} = report, attrs) do
    ensure_access!(scope, report)

    with {:ok, report} <-
           report
           |> Report.changeset(attrs, scope)
           |> Repo.update() do
      {:ok, Repo.preload(report, default_preload())}
    end
  end

  def delete_report(%Scope{} = scope, %Report{} = report) do
    ensure_access!(scope, report)

    Repo.delete(report)
  end

  def change_report(%Scope{} = scope, %Report{} = report \\ %Report{}, attrs \\ %{}) do
    report
    |> Repo.preload(:groups)
    |> Report.changeset(attrs, scope)
  end

  ## Groups

  def create_group(%Scope{} = scope, %Report{} = report, attrs) do
    ensure_access!(scope, report)

    attrs =
      attrs
      |> string_key_map()
      |> Map.put_new("position", next_group_position(report))
      |> Map.put_new("report_id", report.id)

    %ReportGroup{}
    |> ReportGroup.changeset(attrs)
    |> Repo.insert()
  end

  def update_group(%Scope{} = scope, %ReportGroup{} = group, attrs) do
    ensure_access_by_group!(scope, group)

    group
    |> ReportGroup.changeset(attrs)
    |> Repo.update()
  end

  def delete_group(%Scope{} = scope, %ReportGroup{} = group) do
    ensure_access_by_group!(scope, group)

    Repo.delete(group)
  end

  ## Group metrics

  def add_metric_to_group(
        %Scope{} = scope,
        %ReportGroup{} = group,
        %Metric{} = metric,
        attrs \\ %{}
      ) do
    ensure_access_by_group!(scope, group)
    ensure_metric_access!(scope, metric)

    attrs =
      attrs
      |> string_key_map()
      |> Map.put_new("report_group_id", group.id)
      |> Map.put_new("metric_id", metric.id)
      |> Map.put_new("position", next_metric_position(group))

    %ReportGroupMetric{}
    |> ReportGroupMetric.changeset(attrs)
    |> Repo.insert()
  end

  def update_group_metric(%Scope{} = scope, %ReportGroupMetric{} = group_metric, attrs) do
    ensure_access_by_group_metric!(scope, group_metric)

    group_metric
    |> ReportGroupMetric.changeset(attrs)
    |> Repo.update()
  end

  def remove_metric_from_group(%Scope{} = scope, %ReportGroupMetric{} = group_metric) do
    ensure_access_by_group_metric!(scope, group_metric)

    Repo.delete(group_metric)
  end

  def move_metric_to_group(
        %Scope{} = scope,
        %ReportGroupMetric{} = group_metric,
        %ReportGroup{} = target_group,
        opts \\ []
      ) do
    ensure_access_by_group_metric!(scope, group_metric)
    ensure_access_by_group!(scope, target_group)

    before_group_metric_id = Keyword.get(opts, :before_group_metric_id)
    group_metric = Repo.preload(group_metric, :report_group)

    cond do
      group_metric.report_group.report_id != target_group.report_id ->
        {:error, :different_report}

      before_group_metric_id == group_metric.id ->
        {:ok, group_metric}

      true ->
        Repo.transaction(fn ->
          target_metrics =
            Repo.all(
              from gm in ReportGroupMetric,
                where: gm.report_group_id == ^target_group.id and gm.id != ^group_metric.id,
                order_by: [asc: gm.position, asc: gm.id]
            )

          insert_index =
            target_metrics
            |> Enum.find_index(&(&1.id == before_group_metric_id))
            |> case do
              nil -> length(target_metrics)
              idx -> idx
            end

          reordered_metric_ids =
            target_metrics
            |> Enum.map(& &1.id)
            |> List.insert_at(insert_index, group_metric.id)

          if reordered_metric_ids == Enum.map(target_metrics, & &1.id) and
               group_metric.report_group_id == target_group.id do
            group_metric
          else
            reorder_group_metrics(target_group.id, reordered_metric_ids, group_metric.id)

            if group_metric.report_group_id != target_group.id do
              normalize_group_metric_positions(group_metric.report_group_id)
            end

            Repo.get!(ReportGroupMetric, group_metric.id)
          end
        end)
    end
  end

  def metric_results_for_report(%Report{} = report, opts \\ []) do
    limit_per_metric = Keyword.get(opts, :limit, 50)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    metric_ids =
      report.groups
      |> Enum.flat_map(& &1.group_metrics)
      |> Enum.map(& &1.metric_id)

    case metric_ids do
      [] ->
        %{}

      ids ->
        {from_ts, to_ts} = report_time_window(report, now)

        base_query =
          from mr in MetricResult,
            where: mr.metric_id in ^ids,
            order_by: [asc: mr.from_ts]

        time_scoped_query =
          base_query
          |> maybe_time_filter(from_ts, to_ts)
          |> limit(^overall_limit(limit_per_metric, length(ids)))

        Repo.all(time_scoped_query)
        |> Enum.group_by(& &1.metric_id)
    end
  end

  ## Helpers

  defp default_preload do
    [
      :user,
      :team,
      groups:
        {from(g in ReportGroup, order_by: g.position),
         [
           group_metrics:
             {from(gm in ReportGroupMetric, order_by: gm.position), [metric: [:server]]}
         ]}
    ]
  end

  defp accessible_by_scope(query, user_id) do
    query
    |> join(:left, [r], tu in TeamUser, on: tu.team_id == r.team_id)
    |> where(
      [r, tu],
      (r.user_id == ^user_id and not is_nil(r.user_id)) or
        (tu.user_id == ^user_id and tu.role != :invited)
    )
  end

  defp ensure_access!(%Scope{} = scope, %Report{} = report) do
    cond do
      is_nil(report.team_id) and report.user_id == scope.user.id ->
        true

      not is_nil(report.team_id) ->
        QueryCanary.Accounts.user_has_access_to_team?(scope.user.id, report.team_id) ||
          raise AccessError, message: "report not accessible to user"

      true ->
        raise AccessError, message: "report not accessible to user"
    end
  end

  defp ensure_access_by_group!(%Scope{} = scope, %ReportGroup{} = group) do
    group = Repo.preload(group, :report)
    ensure_access!(scope, group.report)
  end

  defp ensure_access_by_group_metric!(%Scope{} = scope, %ReportGroupMetric{} = group_metric) do
    group_metric = Repo.preload(group_metric, report_group: :report)
    ensure_access!(scope, group_metric.report_group.report)
  end

  defp ensure_metric_access!(%Scope{} = scope, %Metric{} = metric) do
    metric = Repo.preload(metric, :server)

    cond do
      metric.user_id == scope.user.id ->
        true

      metric.team_id &&
          QueryCanary.Accounts.user_has_access_to_team?(scope.user.id, metric.team_id) ->
        true

      metric.server_id && metric.server ->
        QueryCanary.Servers.get_server(scope, metric.server_id) && true

      true ->
        raise AccessError, message: "metric not accessible to user"
    end
  end

  defp next_group_position(%Report{} = report) do
    Repo.one(
      from g in ReportGroup,
        where: g.report_id == ^report.id,
        select: coalesce(max(g.position), -1)
    ) + 1
  end

  defp next_metric_position(%ReportGroup{} = group) do
    Repo.one(
      from gm in ReportGroupMetric,
        where: gm.report_group_id == ^group.id,
        select: coalesce(max(gm.position), -1)
    ) + 1
  end

  defp reorder_group_metrics(target_group_id, metric_ids, moving_metric_id) do
    Enum.with_index(metric_ids)
    |> Enum.each(fn {metric_id, index} ->
      updates =
        if metric_id == moving_metric_id do
          [report_group_id: target_group_id, position: index]
        else
          [position: index]
        end

      Repo.update_all(
        from(gm in ReportGroupMetric, where: gm.id == ^metric_id),
        set: updates
      )
    end)
  end

  defp normalize_group_metric_positions(group_id) do
    Repo.all(
      from gm in ReportGroupMetric,
        where: gm.report_group_id == ^group_id,
        order_by: [asc: gm.position, asc: gm.id]
    )
    |> Enum.with_index()
    |> Enum.each(fn {%ReportGroupMetric{id: id}, index} ->
      Repo.update_all(
        from(gm in ReportGroupMetric, where: gm.id == ^id),
        set: [position: index]
      )
    end)
  end

  defp string_key_map(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp string_key_map(other), do: other

  defp maybe_time_filter(query, from_ts, to_ts) do
    query =
      if from_ts do
        from mr in query, where: mr.from_ts >= ^from_ts
      else
        query
      end

    if to_ts do
      from mr in query, where: mr.to_ts <= ^to_ts
    else
      query
    end
  end

  defp overall_limit(limit_per_metric, metric_count) do
    limit_per_metric * max(metric_count, 1)
  end

  defp report_time_window(%Report{} = report, now) do
    tz = report.timezone || "Etc/UTC"

    {:ok, local_now} = DateTime.shift_zone(now, tz)
    local_date = Date.new!(local_now.year, local_now.month, local_now.day)
    range = report.default_range || "30d"

    case range do
      "today" ->
        rolling_day_window(local_date, tz, effective_window_days(report))

      "yesterday" ->
        previous_day_window(local_now, tz)

      "7d" ->
        rolling_day_window(local_date, tz, effective_window_days(report))

      "30d" ->
        rolling_day_window(local_date, tz, effective_window_days(report))

      "ytd" ->
        year_to_date_window(local_date, tz)

      "quarter" ->
        rolling_day_window(local_date, tz, effective_window_days(report))

      _ ->
        rolling_day_window(local_date, tz, effective_window_days(report))
    end
  end

  defp previous_day_window(local_now, tz) do
    local_date = Date.new!(local_now.year, local_now.month, local_now.day)
    local_yesterday = Date.add(local_date, -1)
    start_local = DateTime.new!(local_yesterday, ~T[00:00:00], tz)
    end_local = DateTime.new!(local_date, ~T[00:00:00], tz)
    {shift_to_utc(start_local), shift_to_utc(end_local)}
  end

  defp rolling_day_window(local_date, tz, days) do
    end_local = DateTime.new!(Date.add(local_date, 1), ~T[00:00:00], tz)
    start_local = DateTime.add(end_local, -(days * 86_400), :second)
    {shift_to_utc(start_local), shift_to_utc(end_local)}
  end

  defp year_to_date_window(local_date, tz) do
    start_local = DateTime.new!(Date.new!(local_date.year, 1, 1), ~T[00:00:00], tz)
    end_local = DateTime.new!(Date.add(local_date, 1), ~T[00:00:00], tz)
    {shift_to_utc(start_local), shift_to_utc(end_local)}
  end

  defp shift_to_utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")

  defp effective_window_days(%Report{} = report) do
    max(range_to_days(report.default_range || "30d"), minimum_metric_window_days(report))
  end

  defp minimum_metric_window_days(%Report{} = report) do
    report.groups
    |> Enum.flat_map(& &1.group_metrics)
    |> Enum.map(fn group_metric ->
      case group_metric.metric do
        %Metric{granularity: granularity} -> minimum_granularity_window_days(granularity)
        _ -> 1
      end
    end)
    |> Enum.max(fn -> 1 end)
  end

  defp minimum_granularity_window_days("minute"), do: 1
  defp minimum_granularity_window_days("hour"), do: 7
  defp minimum_granularity_window_days("day"), do: 30
  defp minimum_granularity_window_days("week"), do: 90
  defp minimum_granularity_window_days("month"), do: 90
  defp minimum_granularity_window_days(_), do: 30

  defp range_to_days("today"), do: 1
  defp range_to_days("yesterday"), do: 1
  defp range_to_days("7d"), do: 7
  defp range_to_days("30d"), do: 30
  defp range_to_days("ytd"), do: 366
  defp range_to_days("quarter"), do: 90
  defp range_to_days(_), do: 30
end

defmodule QueryCanary.Reports.AccessError do
  defexception message: "no permission to access"
end
