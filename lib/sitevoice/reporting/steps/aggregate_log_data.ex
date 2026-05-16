defmodule Sitevoice.Steps.AggregateLogData do
  use Reactor.Step

  require Logger

  def run(%{logs: logs, report: report}, _, _) do
    total_labor_hours =
      logs
      |> Enum.flat_map(& &1.labor)
      |> Enum.reduce(0.0, fn entry, acc ->
        hours = to_float(entry["hours"])
        acc + hours
      end)

    total_headcount_days =
      logs
      |> Enum.flat_map(& &1.labor)
      |> Enum.reduce(0, fn entry, acc ->
        acc + (entry["headcount"] || 0)
      end)

    labor_by_trade =
      logs
      |> Enum.flat_map(& &1.labor)
      |> Enum.group_by(&(&1["trade"] || "Unknown"))
      |> Enum.map(fn {trade, entries} ->
        %{
          "trade" => trade,
          "total_headcount" => Enum.sum(Enum.map(entries, &(&1["headcount"] || 0))),
          "total_hours" => Enum.reduce(entries, 0.0, &(to_float(&1["hours"]) + &2))
        }
      end)

    daily_snapshot =
      Enum.map(logs, fn log ->
        day_headcount = Enum.reduce(log.labor, 0, fn e, acc -> acc + (e["headcount"] || 0) end)
        day_hours = Enum.reduce(log.labor, 0.0, fn e, acc -> acc + to_float(e["hours"]) end)

        %{
          "date" => Date.to_string(log.date),
          "foreman" => (log.foreman && log.foreman.name) || "—",
          "headcount" => day_headcount,
          "hours" => day_hours,
          "status" => to_string(log.status)
        }
      end)

    weather =
      logs
      |> Enum.map(& &1.weather)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    result = %{
      project_id: report.project_id,
      week_start: report.week_start,
      week_end: report.week_end,
      daily_log_count: length(logs),
      total_labor_hours: total_labor_hours,
      total_headcount_days: total_headcount_days,
      labor_by_trade: labor_by_trade,
      progress: Enum.flat_map(logs, & &1.progress),
      equipment: Enum.flat_map(logs, & &1.equipment),
      materials: Enum.flat_map(logs, & &1.materials),
      delays: Enum.flat_map(logs, & &1.delays),
      safety: Enum.flat_map(logs, & &1.safety),
      weather: weather,
      daily_snapshot: daily_snapshot
    }

    Logger.info("AggregateLogData complete",
      log_count: result.daily_log_count,
      total_hours: result.total_labor_hours,
      delays: length(result.delays)
    )

    {:ok, result}
  end

  def compensate(_, _, _, _), do: :ok

  defp to_float(nil), do: 0.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
