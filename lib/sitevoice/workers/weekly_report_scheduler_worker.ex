defmodule Sitevoice.Workers.WeeklyReportSchedulerWorker do
  use Oban.Worker, queue: :reports, max_attempts: 3

  require Ash.Query
  require Logger

  alias Sitevoice.Accounts.Organization
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.WeeklyReport

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.metadata(oban_job_id: job_id)
    Logger.info("WeeklyReportSchedulerWorker starting")

    {week_start, week_end} = current_week()
    Logger.info("WeeklyReportSchedulerWorker week range", week_start: week_start, week_end: week_end)

    orgs = Ash.read!(Organization, authorize?: false)

    Enum.each(orgs, fn org ->
      org_id = to_string(org.id)

      projects =
        Project
        |> Ash.Query.for_read(:list_active)
        |> Ash.read!(authorize?: false, tenant: org_id)

      Enum.each(projects, fn project ->
        schedule_report(org_id, project.id, week_start, week_end)
      end)
    end)

    :ok
  end

  def current_week do
    today = Date.utc_today()
    dow = Date.day_of_week(today)
    week_start = Date.add(today, 1 - dow)
    week_end = Date.add(week_start, 6)
    {week_start, week_end}
  end

  defp schedule_report(org_id, project_id, week_start, week_end) do
    case Sitevoice.Reporting.get_weekly_report_by_week(project_id, week_start,
           authorize?: false,
           tenant: org_id
         ) do
      {:ok, []} ->
        create_and_enqueue(org_id, project_id, week_start, week_end)

      {:ok, [existing | _]} ->
        Logger.debug("WeeklyReportScheduler skipping — report exists",
          report_id: existing.id,
          project_id: project_id,
          status: existing.status
        )

      {:error, reason} ->
        Logger.error("WeeklyReportScheduler failed to check existing report",
          project_id: project_id,
          reason: inspect(reason)
        )
    end
  end

  defp create_and_enqueue(org_id, project_id, week_start, week_end) do
    attrs = %{
      project_id: project_id,
      organization_id: org_id,
      week_start: week_start,
      week_end: week_end
    }

    case WeeklyReport
         |> Ash.Changeset.for_create(:create, attrs, authorize?: false, tenant: org_id)
         |> Ash.create() do
      {:ok, report} ->
        Logger.info("WeeklyReportScheduler created report", report_id: report.id, project_id: project_id)

        %{"report_id" => report.id, "organization_id" => org_id}
        |> Sitevoice.Workers.WeeklyReportWorker.new()
        |> Oban.insert()

      {:error, reason} ->
        Logger.error("WeeklyReportScheduler failed to create report",
          project_id: project_id,
          reason: inspect(reason)
        )
    end
  end
end
