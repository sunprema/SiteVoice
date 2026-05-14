defmodule Sitevoice.Projects.Calculations.LastReportDate do
  use Ash.Resource.Calculation

  require Ash.Query

  @impl true
  def calculate(records, _opts, _context) do
    results =
      Enum.map(records, fn record ->
        logs =
          Ash.Query.new(Sitevoice.Reporting.DailyLog)
          |> Ash.Query.filter(project_id == ^record.id and status == :submitted)
          |> Ash.Query.sort(date: :desc)
          |> Ash.Query.limit(1)
          |> Ash.Query.select([:date])
          |> Ash.read!(tenant: to_string(record.organization_id), authorize?: false)

        case logs do
          [log | _] -> log.date
          [] -> nil
        end
      end)

    {:ok, results}
  end
end
