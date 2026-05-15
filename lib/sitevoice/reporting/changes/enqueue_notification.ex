defmodule Sitevoice.Reporting.Changes.EnqueueNotification do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _cs, log ->
      Logger.info("EnqueueNotification enqueuing NotifyPmWorker job",
        log_id: log.id,
        org_id: log.organization_id
      )

      case %{log_id: log.id, organization_id: log.organization_id}
           |> Sitevoice.Workers.NotifyPmWorker.new()
           |> Oban.insert() do
        {:ok, job} ->
          Logger.info("EnqueueNotification NotifyPmWorker job enqueued",
            oban_job_id: job.id,
            log_id: log.id
          )

        {:error, reason} ->
          Logger.error("EnqueueNotification failed to enqueue NotifyPmWorker job",
            log_id: log.id,
            reason: inspect(reason)
          )
      end

      {:ok, log}
    end)
  end
end
