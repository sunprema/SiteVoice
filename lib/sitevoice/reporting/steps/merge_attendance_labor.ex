defmodule Sitevoice.Steps.MergeAttendanceLabor do
  use Reactor.Step

  require Logger

  def run(%{attendance: attendance_rows, claude_labor: claude_labor}, _, _) do
    roster_labor =
      attendance_rows
      |> Enum.filter(&(&1.headcount_present > 0))
      |> Enum.map(fn row ->
        %{
          "crew" => row.crew_template.name,
          "trade" => to_string(row.crew_template.trade),
          "headcount" => row.headcount_present,
          "hours" => row.hours,
          "subcontractor" => row.crew_template.subcontractor || ""
        }
      end)

    roster_names =
      MapSet.new(roster_labor, &String.downcase(&1["crew"]))

    novel_claude =
      Enum.reject(claude_labor, fn entry ->
        crew_name = entry["crew"] || entry[:crew] || ""
        MapSet.member?(roster_names, String.downcase(to_string(crew_name)))
      end)

    merged = roster_labor ++ novel_claude

    Logger.info("MergeAttendanceLabor merged #{length(roster_labor)} roster + #{length(novel_claude)} claude entries")

    {:ok, merged}
  end

  def compensate(_, _, _, _), do: :ok
end
