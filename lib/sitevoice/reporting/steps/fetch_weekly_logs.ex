defmodule Sitevoice.Steps.FetchWeeklyLogs do
  use Reactor.Step

  require Ash.Query
  require Logger

  def run(%{report: report, organization_id: org_id}, _, _) do
    Logger.info("FetchWeeklyLogs loading logs",
      project_id: report.project_id,
      week_start: report.week_start,
      week_end: report.week_end,
      org_id: org_id
    )

    logs =
      Sitevoice.Reporting.DailyLog
      |> Ash.Query.for_read(:list_for_date_range, %{
          project_id: report.project_id,
          from: report.week_start,
          to: report.week_end
        })
      |> Ash.read!(authorize?: false, tenant: org_id, load: [:foreman])

    submitted = Enum.filter(logs, &(&1.status == :submitted))

    Logger.info("FetchWeeklyLogs found submitted logs",
      total: length(logs),
      submitted: length(submitted)
    )

    {:ok, submitted}
  end

  def compensate(_, _, _, _), do: :ok
end
