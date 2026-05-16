defmodule Sitevoice.Workers.WeeklyReportNotifyWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query
  require Logger

  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.ProjectMembership
  alias Sitevoice.Reporting.WeeklyReport
  alias Sitevoice.Reporting.Emails.WeeklyReportEmail
  alias Sitevoice.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"report_id" => report_id, "organization_id" => org_id}}) do
    Logger.metadata(report_id: report_id, org_id: org_id, oban_job_id: job_id)
    Logger.info("WeeklyReportNotifyWorker starting")

    report =
      Ash.get!(WeeklyReport, report_id,
        authorize?: false,
        tenant: org_id,
        load: [:project, :organization]
      )

    if is_nil(report.pdf_key) do
      Logger.warning("WeeklyReportNotifyWorker: report has no PDF key", report_id: report_id)
      {:error, :no_pdf}
    else
      memberships =
        ProjectMembership
        |> Ash.Query.filter(project_id == ^report.project_id and role == :pm)
        |> Ash.read!(authorize?: false, tenant: org_id)

      Logger.info("WeeklyReportNotifyWorker found PMs", count: length(memberships))

      case Storage.fetch(report.pdf_key) do
        {:ok, pdf_binary} ->
          Enum.each(memberships, fn membership ->
            pm = Ash.get!(User, membership.user_id, authorize?: false, tenant: org_id)

            email = WeeklyReportEmail.report_ready(report, pdf_binary, pm)

            case Sitevoice.Mailer.deliver(email) do
              {:ok, _} ->
                Logger.info("WeeklyReportNotifyWorker email delivered", pm_email: pm.email)

              {:error, reason} ->
                Logger.error("WeeklyReportNotifyWorker delivery failed",
                  pm_email: pm.email,
                  reason: inspect(reason)
                )
            end
          end)

          :ok

        {:error, reason} ->
          Logger.error("WeeklyReportNotifyWorker failed to fetch PDF",
            pdf_key: report.pdf_key,
            reason: inspect(reason)
          )
          {:error, reason}
      end
    end
  end
end
