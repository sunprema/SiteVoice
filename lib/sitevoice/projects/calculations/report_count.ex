defmodule Sitevoice.Projects.Calculations.ReportCount do
  use Ash.Resource.Calculation

  require Ash.Query

  @impl true
  def calculate(records, _opts, _context) do
    results =
      Enum.map(records, fn record ->
        Ash.Query.new(Sitevoice.Reporting.DailyLog)
        |> Ash.Query.filter(project_id == ^record.id and status == :submitted)
        |> Ash.count!(tenant: to_string(record.organization_id), authorize?: false)
      end)

    {:ok, results}
  end
end
