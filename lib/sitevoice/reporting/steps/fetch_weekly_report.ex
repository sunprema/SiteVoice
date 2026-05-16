defmodule Sitevoice.Steps.FetchWeeklyReport do
  use Reactor.Step

  require Logger

  alias Sitevoice.Reporting.WeeklyReport

  def run(%{report_id: report_id, organization_id: org_id}, _, _) do
    Logger.debug("FetchWeeklyReport loading report", report_id: report_id, org_id: org_id)

    result =
      Ash.get(WeeklyReport, report_id,
        load: [:organization, :project],
        authorize?: false,
        tenant: org_id
      )

    case result do
      {:ok, report} ->
        Logger.info("FetchWeeklyReport loaded", report_id: report_id, status: report.status)

      {:error, reason} ->
        Logger.error("FetchWeeklyReport failed",
          report_id: report_id,
          reason: inspect(reason)
        )
    end

    result
  end

  def compensate(_, _, _, _), do: :ok

  def undo(report, _arguments, _context, _options) do
    org_id = to_string(report.organization_id)

    report
    |> Ash.Changeset.for_update(:mark_failed, %{}, authorize?: false, tenant: org_id)
    |> Ash.update()

    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      "org:#{org_id}:weekly_report:#{report.id}",
      {:weekly_report_status, %{report_id: report.id, status: :failed}}
    )

    :ok
  end
end
