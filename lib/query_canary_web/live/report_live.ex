defmodule QueryCanaryWeb.ReportLive do
  alias QueryCanary.Checks.CheckResult
  alias QueryCanary.Checks.Check
  use QueryCanaryWeb, :live_view
  import Phoenix.HTML.Form
  import Phoenix.Component

  import Ecto.Query

  @days_to_show 14

  defmodule MetricCheck do
    defstruct [:name, :group, :query, :opts]
  end

  def metric_data(dates) do
    server = QueryCanary.Repo.one(from s in QueryCanary.Servers.Server, where: s.id == 1)

    [
      %MetricCheck{
        name: "Manual Listing Starts",
        group: "Private Seller",
        query: """
        SELECT
        COUNT(*) AS total_listings
        FROM
        insight_myvehicle as imv
        join insight_user as iu on imv.user_id = iu.id
        WHERE
        imv.listing_type LIKE 'SIMPLE'
        and email not like '%@classic.com%'
        and iu.dealer_id is null
        and date(imv.created) = $1;
        """
      },
      %MetricCheck{
        name: "Manual Listing Completions",
        group: "Private Seller",
        query: """
        SELECT
        COUNT(*) AS total_listings
        FROM
        insight_myvehicle as imv
        join insight_user as iu on imv.user_id = iu.id
        join insight_vehicle as iv on iv.id = imv.vehicle_id
        WHERE
        imv.listing_type LIKE 'SIMPLE'
        and email not like '%@classic.com%'
        and iu.dealer_id is null
        and (imv.status like 'ACTIVE' or imv.status like 'CLOSED')
        and iv.enabled is TRUE
        and date(iv.created) = $1;
        """
      },
      %MetricCheck{
        name: "Created Vehicles",
        group: "vehicles",
        query: "select count(*) from insight_vehicle where date(created) = $1;"
      }
      #       %MetricCheck{
      #         name: "Auctions",
      #         group: "vehicles",
      #         query:
      #           "select count(*) from insight_vehicle where listing_type = 'AUCTION' and date(created) = $1;"
      #       },
      #       %MetricCheck{
      #         name: "Dealers",
      #         group: "vehicles",
      #         query:
      #           "select count(*) from insight_vehicle where listing_type = 'DEALER' and date(created) = $1;"
      #       },
      #       %MetricCheck{
      #         name: "Extended",
      #         group: "vehicles",
      #         query:
      #           "select count(*) from insight_vehicle where listing_type = 'EXTENDED' and date(created) = $1;"
      #       },
      #       %MetricCheck{
      #         name: "Average Price",
      #         group: "vehicles",
      #         query: "select avg(price_usd) from insight_vehicle where date(created) = $1;",
      #         opts: [money: true]
      #       },
      #       %MetricCheck{
      #         name: "Created Users",
      #         group: "users",
      #         query: "select count(*) from insight_user where date(date_joined) = $1;"
      #       },
      #       %MetricCheck{
      #         name: "Created Amplify Listings",
      #         group: "private seller",
      #         query: "select count(*)
      # from insight_myvehicle mv
      # join insight_myvehiclestatuschange mvsc on mv.id = mvsc.my_vehicle_id
      # where mvsc.status = 'ACTIVE' and date(mvsc.created) = $1;"
      #       }
    ]
    |> Enum.map(fn mc ->
      values =
        Enum.map(dates, fn date ->
          case QueryCanary.Connections.ConnectionManager.run_query(server, mc.query, [date]) do
            {:ok, %{rows: [row | _tl]}} ->
              {date,
               Map.values(row)
               |> hd()
               |> parse_value()}
          end
        end)
        |> Enum.into(%{})

      %{
        group: mc.group,
        name: mc.name,
        values: values,
        opts: mc.opts || %{}
      }
    end)
    |> dbg()
  end

  defp parse_value(%Decimal{} = dec) do
    dec
    |> Decimal.round()
    |> Decimal.to_integer()
  end

  defp parse_value(x) when is_integer(x), do: x
  defp parse_value(_), do: 0

  def check_data(days) do
    QueryCanary.Repo.all(from(cr in Check))
    |> QueryCanary.Repo.preload([:results, :server])
    |> Enum.map(fn check ->
      results =
        Enum.slice(check.results, 0, length(days))
        |> Enum.map(fn x -> x.result end)
        |> List.flatten()
        |> Enum.reduce(%{}, fn map, acc ->
          Enum.reduce(map, acc, fn {k, v}, acc2 ->
            Map.update(acc2, k, [v], &[v | &1])
          end)
        end)
        |> Enum.into(%{}, fn {k, vs} -> {k, Enum.reverse(vs)} end)

      for {k, values} <- results do
        %{
          group: check.server.name,
          name: "#{check.name} (#{k})",
          values:
            Enum.map(Enum.with_index(days), fn {d, i} ->
              v =
                case Enum.at(values, i, 0) do
                  {k, v} -> v
                  v -> v
                end

              {d, if(is_integer(v), do: v, else: 0)}
            end)
            |> Enum.into(%{}),
          opts: %{}
        }
      end
    end)
    |> List.flatten()
  end

  # ---- Mount ----
  def mount(_params, _session, socket) do
    days =
      0..@days_to_show
      |> Enum.map(&(Date.utc_today() |> Date.add(-&1)))
      |> Enum.reverse()

    days = Date.range(~D[2025-03-01], ~D[2025-03-14], 1)
    days = Enum.take(days, Enum.count(days))

    metrics =
      check_data(days)

    metrics = metric_data(days)

    # ++
    # [
    #   %{
    #     group: "Foo",
    #     name: "Bar",
    #     values: Enum.map(Enum.with_index(days), fn {d, i} -> {d, i} end) |> Enum.into(%{}),
    #     opts: %{}
    #   }
    # ] ++
    # seed_group(
    #   "Acquisition",
    #   ["Website Sessions", "Signups", "Activated Users", "Paid Conversions"],
    #   days
    # ) ++
    # seed_group("Engagement", ["DAU", "WAU", "MAU", "Retention D30 (%)"], days, pct: true) ++
    # seed_group(
    #   "Revenue",
    #   ["MRR ($)", "ARR ($)", "Net New MRR ($)", "Expansion MRR ($)", "Churn MRR ($)"],
    #   days,
    #   money: true
    # ) ++
    # seed_group(
    #   "Product",
    #   ["Queries Run", "Checks Executed", "Alerts Fired", "Median Query ms"],
    #   days
    # ) ++
    # seed_group(
    #   "Infrastructure",
    #   ["API Errors", "Error Rate (%)", "P95 Latency ms", "Background Jobs"],
    #   days
    # )

    metrics =
      Enum.map(metrics, fn m ->
        values_list = Enum.map(days, &Map.fetch!(m.values, &1))
        {min, max} = Enum.min_max(values_list)

        avg =
          Enum.sum_by(values_list, fn x ->
            case x do
              %Decimal{} = dec ->
                Decimal.to_float(dec)

              x ->
                x
            end
          end) / max(length(values_list), 1)

        Map.merge(m, %{min: min, max: max, avg: avg})
      end)

    {:ok,
     socket
     |> assign(:days, days)
     |> assign(:metrics, metrics)
     |> assign(:groups, Enum.uniq(Enum.map(metrics, & &1.group)))}
  end

  # ---- Render ----
  def render(assigns) do
    ~H"""
    <div class="p-4 space-y-4">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-semibold tracking-tight">Company Metrics Report</h1>
        <div class="text-xs text-slate-500">
          Showing last {length(@days)} days (ending {@days |> List.last() |> format_day()})
        </div>
      </div>

      <div class="overflow-x-auto rounded border border-slate-200 bg-white shadow-sm">
        <table class="min-w-full border-collapse text-[11px] leading-tight">
          <thead class="bg-slate-50 sticky top-0 z-20">
            <tr>
              <th class="sticky left-0 z-30 bg-slate-50 px-3 py-2 text-left font-medium text-slate-600 border-b border-slate-200 w-48">
                Metric
              </th>
              <%= for day <- @days do %>
                <th class="px-2 py-2 text-center font-medium text-slate-600 border-b border-slate-200 w-16">
                  <div class="flex flex-col items-center gap-0.5">
                    <span>{format_day_short(day)}</span>
                    <span class="text-[9px] font-normal text-slate-400">{day_of_week(day)}</span>
                  </div>
                </th>
              <% end %>
              <th class="px-2 py-2 text-center font-medium text-slate-600 border-b border-slate-200 w-14">
                Δ 7d
              </th>
              <th class="px-2 py-2 text-center font-medium text-slate-600 border-b border-slate-200 w-14">
                Δ 14d
              </th>
              <th class="px-2 py-2 text-center font-medium text-slate-600 border-b border-slate-200 w-14">
                Avg
              </th>
            </tr>
          </thead>
          <tbody>
            <%= for group <- @groups do %>
              <tr>
                <td
                  class="sticky left-0 z-10 bg-slate-100/90 backdrop-blur px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-t border-b border-slate-200"
                  colspan={length(@days) + 4}
                >
                  {group}
                </td>
              </tr>
              <%= for metric <- Enum.filter(@metrics, & &1.group == group) do %>
                <tr class="hover:bg-slate-50">
                  <td class="sticky left-0 z-10 bg-white px-3 py-1.5 font-medium text-slate-700 border-b border-slate-100">
                    <div class="flex items-center gap-1">
                      <span class="truncate">{metric.name}</span>
                      <%= if metric.opts[:pct] do %>
                        <span class="text-[9px] text-slate-400 font-normal">%</span>
                      <% end %>
                    </div>
                  </td>
                  <%= for day <- @days do %>
                    <% value = Map.fetch!(metric.values, day) %>
                    <% cls = heat_class(value, metric.min, metric.max) %>
                    <td
                      class={"relative px-1.5 py-1 text-center align-middle border-b border-slate-100 #{cls}"}
                      title={"#{metric.name} #{format_day(day)}: #{fmt(value, metric.opts)}"}
                    >
                      <div class="font-medium tabular-nums">
                        {fmt_compact(value, metric.opts)}
                      </div>
                      <div class="absolute inset-0 pointer-events-none">
                        <div class={"h-full w-full opacity-15 " <> heat_bg_color(value, metric.min, metric.max)}>
                        </div>
                      </div>
                    </td>
                  <% end %>
                  <% latest = Map.fetch!(metric.values, List.last(@days)) %>
                  <% week_ago = Map.get(metric.values, Enum.at(@days, -8)) %>
                  <% fortnight_ago = Map.get(metric.values, Enum.at(@days, 0)) %>
                  <td class="px-2 py-1 text-center border-b border-slate-100">
                    <.delta_chip latest={latest} past={week_ago} />
                  </td>
                  <td class="px-2 py-1 text-center border-b border-slate-100">
                    <.delta_chip latest={latest} past={fortnight_ago} />
                  </td>
                  <td class="px-2 py-1 text-center border-b border-slate-100 text-slate-600 tabular-nums">
                    {fmt(round(metric.avg), metric.opts)}
                  </td>
                </tr>
              <% end %>
            <% end %>
            <tr>
              <td
                class="sticky left-0 z-10 bg-slate-100/90 backdrop-blur px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wide text-slate-500 border-t border-b border-slate-200"
                colspan={length(@days) + 4}
              >
                <.link patch={~p"/report/new"}>Create Metric</.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="flex items-center gap-4 pt-2">
        <div class="flex items-center gap-1 text-[10px] text-slate-500">
          <span class="inline-block h-3 w-5 rounded bg-emerald-200"></span> High
        </div>
        <div class="flex items-center gap-1 text-[10px] text-slate-500">
          <span class="inline-block h-3 w-5 rounded bg-slate-100 border border-slate-200"></span> Mid
        </div>
        <div class="flex items-center gap-1 text-[10px] text-slate-500">
          <span class="inline-block h-3 w-5 rounded bg-rose-200"></span> Low
        </div>
      </div>
    </div>
    """
  end

  # ---- Function Component (HEEx) ----
  attr :latest, :integer, required: true
  attr :past, :integer

  defp delta_chip(assigns) do
    cond do
      is_nil(assigns.past) ->
        ~H"""
        <span class="text-slate-400">—</span>
        """

      assigns.past == 0 ->
        ~H"""
        <span class="text-slate-400">∞</span>
        """

      true ->
        diff = assigns.latest - assigns.past
        pct = diff / assigns.past

        cls =
          cond do
            pct > 0.15 -> "bg-emerald-100 text-emerald-700 border-emerald-200"
            pct > 0.03 -> "bg-emerald-50 text-emerald-600 border-emerald-200"
            pct < -0.15 -> "bg-rose-100 text-rose-700 border-rose-200"
            pct < -0.03 -> "bg-rose-50 text-rose-600 border-rose-200"
            true -> "bg-slate-50 text-slate-600 border-slate-200"
          end

        arrow =
          cond do
            diff > 0 -> "▲"
            diff < 0 -> "▼"
            true -> "■"
          end

        pct_str =
          pct
          |> Kernel.*(100.0)
          |> Float.round(1)
          |> :erlang.float_to_binary(decimals: 1)

        assigns =
          assigns
          |> Map.put(:cls, cls)
          |> Map.put(:arrow, arrow)
          |> Map.put(:pct_str, pct_str)
          |> Map.put(:diff, diff)

        ~H"""
        <span
          class={"inline-block px-1.5 py-0.5 rounded border text-[10px] font-medium tabular-nums #{@cls}"}
          title={"Δ #{@diff} (#{@pct_str}%)"}
        >
          {@arrow} {@pct_str}%
        </span>
        """
    end
  end

  # ---- Helpers ----
  defp seed_group(group, names, days, opts \\ []) do
    Enum.map(names, fn name ->
      seed = :erlang.phash2(name)
      base = if opts[:pct], do: 60 + rem(seed, 30), else: 10_000 + rem(seed, 80_000)
      volatility = if opts[:pct], do: 6, else: 0.18

      values =
        Enum.reduce(days, %{}, fn day, acc ->
          t = Date.diff(day, List.first(days))
          drift = :math.sin(t / 3) * volatility
          noise = (:rand.uniform() - 0.5) * volatility
          modifier = 1.0 + drift + noise
          raw_val = round(base * modifier)

          v =
            cond do
              opts[:pct] -> Enum.min([Enum.max([raw_val, 10]), 100])
              opts[:money] -> raw_val + rem(seed, 5000)
              true -> raw_val
            end

          Map.put(acc, day, v)
        end)

      %{group: group, name: name, values: values, opts: Map.new(opts)}
    end)
  end

  defp format_day(d), do: Calendar.strftime(d, "%Y-%m-%d")
  defp format_day_short(d), do: Calendar.strftime(d, "%m-%d")
  defp day_of_week(d), do: Calendar.strftime(d, "%a")

  defp heat_class(v, min, max) when max == min, do: "text-slate-600"

  defp heat_class(v, min, max) do
    ratio = (v - min) / max(1, max - min)

    cond do
      ratio >= 0.75 -> "text-emerald-700"
      ratio >= 0.50 -> "text-emerald-600"
      ratio >= 0.25 -> "text-slate-600"
      ratio >= 0.10 -> "text-rose-600"
      true -> "text-rose-700"
    end
  end

  defp heat_bg_color(v, min, max) when max == min, do: "bg-slate-100"

  defp heat_bg_color(v, min, max) do
    ratio = (v - min) / max(1, max - min)

    cond do
      ratio >= 0.75 -> "bg-emerald-300"
      ratio >= 0.50 -> "bg-emerald-200"
      ratio >= 0.25 -> "bg-slate-100"
      ratio >= 0.10 -> "bg-rose-200"
      true -> "bg-rose-300"
    end
  end

  defp fmt(v, opts) do
    cond do
      opts[:pct] -> "#{v}%"
      opts[:money] -> "$" <> to_compact(v)
      true -> to_compact(v)
    end
  end

  defp fmt_compact(v, opts), do: fmt(v, opts)

  defp to_compact(v) when v >= 1_000_000,
    do: :io_lib.format("~.1fM", [v / 1_000_000]) |> IO.iodata_to_binary()

  defp to_compact(v) when v >= 10_000,
    do: :io_lib.format("~.1fK", [v / 1_000]) |> IO.iodata_to_binary()

  defp to_compact(v), do: Integer.to_string(v)
end
