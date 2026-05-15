defmodule Sitevoice.Workers.DailyReminderWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query
  require Logger

  alias Sitevoice.Accounts.{Organization, User}
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.Emails.DailyLogEmail

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.metadata(oban_job_id: job_id)
    today = Date.utc_today()
    Logger.info("DailyReminderWorker starting", date: Date.to_string(today))

    orgs =
      Organization
      |> Ash.Query.filter(active == true)
      |> Ash.read!(authorize?: false)

    org_count = length(orgs)
    Logger.info("DailyReminderWorker processing active organizations", org_count: org_count)

    reminders_sent = 0

    reminders_sent =
      Enum.reduce(orgs, reminders_sent, fn org, acc ->
        Logger.debug("DailyReminderWorker processing org", org_id: org.id, org_name: org.name)

        foremen =
          User
          |> Ash.Query.filter(role == :foreman)
          |> Ash.read!(authorize?: false, tenant: to_string(org.id))

        foreman_count = length(foremen)

        Logger.debug("DailyReminderWorker found foremen in org",
          org_id: org.id,
          foreman_count: foreman_count
        )

        Enum.reduce(foremen, acc, fn foreman, inner_acc ->
          submitted_today =
            DailyLog
            |> Ash.Query.filter(
              foreman_id == ^foreman.id and status == :submitted and date == ^today
            )
            |> Ash.Query.limit(1)
            |> Ash.read!(authorize?: false, tenant: to_string(org.id))

          if submitted_today == [] do
            Logger.info("DailyReminderWorker sending reminder",
              foreman_id: foreman.id,
              foreman_email: foreman.email,
              org_id: org.id
            )

            email = DailyLogEmail.daily_reminder(foreman)

            case Sitevoice.Mailer.deliver(email) do
              {:ok, _} ->
                :telemetry.execute([:sitevoice, :notification, :reminder_delivered], %{}, %{
                  foreman_id: foreman.id,
                  org_id: org.id
                })

                inner_acc + 1

              {:error, deliver_err} ->
                Logger.error("DailyReminderWorker failed to deliver reminder",
                  foreman_email: foreman.email,
                  reason: inspect(deliver_err)
                )

                inner_acc
            end
          else
            Logger.debug("DailyReminderWorker foreman already submitted today, skipping",
              foreman_id: foreman.id
            )

            inner_acc
          end
        end)
      end)

    Logger.info("DailyReminderWorker completed", reminders_sent: reminders_sent)
    :ok
  end
end
