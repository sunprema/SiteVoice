defmodule Sitevoice.Workers.WeeklyReportWorker do
  use Oban.Worker, queue: :reports, max_attempts: 3

  require Logger

  alias Sitevoice.Reporting.WeeklyReport
  alias Sitevoice.Reporting.Reactors.GenerateWeeklyReport

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"report_id" => report_id, "organization_id" => org_id}}) do
    Logger.metadata(report_id: report_id, org_id: org_id, oban_job_id: job_id)
    Logger.info("WeeklyReportWorker starting")

    report =
      Ash.get!(WeeklyReport, report_id,
        authorize?: false,
        tenant: org_id
      )

    report
    |> Ash.Changeset.for_update(:mark_generating, %{}, authorize?: false, tenant: org_id)
    |> Ash.update!()

    case Reactor.run(GenerateWeeklyReport, %{report_id: report_id, organization_id: org_id}) do
      {:ok, _updated_report} ->
        Logger.info("WeeklyReportWorker reactor succeeded", report_id: report_id)

        %{"report_id" => report_id, "organization_id" => org_id}
        |> Sitevoice.Workers.WeeklyReportNotifyWorker.new()
        |> Oban.insert()

        :ok

      {:error, reason} ->
        Logger.error("WeeklyReportWorker reactor failed",
          report_id: report_id,
          reason: inspect(reason)
        )
        {:error, reason}
    end
  end
end
