defmodule Sitevoice.Workers.NotifyPmWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query

  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.ProjectMembership
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.Emails.DailyLogEmail
  alias Sitevoice.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}) do
    log =
      Ash.get!(DailyLog, log_id,
        authorize?: false,
        tenant: org_id,
        load: [:project, :foreman]
      )

    if is_nil(log.pdf_key) do
      {:error, :no_pdf}
    else
      memberships =
        ProjectMembership
        |> Ash.Query.filter(project_id == ^log.project_id and role == :pm)
        |> Ash.read!(authorize?: false, tenant: org_id)

      case Storage.fetch(log.pdf_key) do
        {:ok, pdf_binary} ->
          Enum.each(memberships, fn membership ->
            pm = Ash.get!(User, membership.user_id, authorize?: false, tenant: org_id)
            email = DailyLogEmail.report_ready(log, pdf_binary, pm)
            Sitevoice.Mailer.deliver(email)
          end)

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
