defmodule Sitevoice.Workers.DailyReminderWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Ash.Query

  alias Sitevoice.Accounts.{Organization, User}
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.Emails.DailyLogEmail

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    orgs =
      Organization
      |> Ash.Query.filter(active == true)
      |> Ash.read!(authorize?: false)

    Enum.each(orgs, fn org ->
      foremen =
        User
        |> Ash.Query.filter(role == :foreman)
        |> Ash.read!(authorize?: false, tenant: to_string(org.id))

      Enum.each(foremen, fn foreman ->
        submitted_today =
          DailyLog
          |> Ash.Query.filter(foreman_id == ^foreman.id and status == :submitted and date == ^today)
          |> Ash.Query.limit(1)
          |> Ash.read!(authorize?: false, tenant: to_string(org.id))

        if submitted_today == [] do
          email = DailyLogEmail.daily_reminder(foreman)
          Sitevoice.Mailer.deliver(email)
        end
      end)
    end)

    :ok
  end
end
