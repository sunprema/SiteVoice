defmodule Sitevoice.Workers.NotifyPmWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query
  require Logger

  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.ProjectMembership
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.Emails.DailyLogEmail
  alias Sitevoice.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"log_id" => log_id, "organization_id" => org_id}}) do
    Logger.metadata(log_id: log_id, org_id: org_id, oban_job_id: job_id)
    Logger.info("NotifyPmWorker starting")

    log =
      Ash.get!(DailyLog, log_id,
        authorize?: false,
        tenant: org_id,
        load: [:project, :foreman]
      )

    if is_nil(log.pdf_key) do
      Logger.warning("NotifyPmWorker: log has no PDF key yet, cannot notify PMs",
        log_id: log_id,
        log_status: log.status
      )

      {:error, :no_pdf}
    else
      memberships =
        ProjectMembership
        |> Ash.Query.filter(project_id == ^log.project_id and role == :pm)
        |> Ash.read!(authorize?: false, tenant: org_id)

      pm_count = length(memberships)
      Logger.info("NotifyPmWorker found PMs to notify", pm_count: pm_count, log_id: log_id)

      case Storage.fetch(log.pdf_key) do
        {:ok, pdf_binary} ->
          Logger.debug("NotifyPmWorker fetched PDF", pdf_bytes: byte_size(pdf_binary))

          Enum.each(memberships, fn membership ->
            pm = Ash.get!(User, membership.user_id, authorize?: false, tenant: org_id)

            Logger.info("NotifyPmWorker sending email to PM",
              pm_id: pm.id,
              pm_email: pm.email,
              log_id: log_id
            )

            email = DailyLogEmail.report_ready(log, pdf_binary, pm)

            case Sitevoice.Mailer.deliver(email) do
              {:ok, _} ->
                :telemetry.execute([:sitevoice, :notification, :email_delivered], %{}, %{
                  recipient: pm.email,
                  log_id: log_id,
                  org_id: org_id
                })

                Logger.info("NotifyPmWorker email delivered", pm_email: pm.email)

              {:error, deliver_err} ->
                Logger.error("NotifyPmWorker email delivery failed",
                  pm_email: pm.email,
                  reason: inspect(deliver_err)
                )
            end
          end)

          :ok

        {:error, reason} ->
          Logger.error("NotifyPmWorker failed to fetch PDF from storage",
            pdf_key: log.pdf_key,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    end
  end
end
