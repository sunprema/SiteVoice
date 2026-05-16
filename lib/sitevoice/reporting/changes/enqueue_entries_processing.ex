defmodule Sitevoice.Reporting.Changes.EnqueueEntriesProcessing do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      Logger.info("EnqueueEntriesProcessing enqueuing EntriesProcessorWorker",
        log_id: log.id,
        org_id: log.organization_id
      )

      job =
        %{log_id: log.id, organization_id: log.organization_id}
        |> Sitevoice.Workers.EntriesProcessorWorker.new()
        |> Oban.insert!()

      Logger.info("EnqueueEntriesProcessing job enqueued",
        oban_job_id: job.id,
        log_id: log.id
      )

      {:ok, log}
    end)
  end
end
