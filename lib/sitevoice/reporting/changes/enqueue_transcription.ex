defmodule Sitevoice.Reporting.Changes.EnqueueTranscription do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, entry ->
      Logger.info("EnqueueTranscription enqueuing TranscribeEntryWorker",
        entry_id: entry.id,
        org_id: entry.organization_id
      )

      job =
        %{entry_id: entry.id, organization_id: entry.organization_id}
        |> Sitevoice.Workers.TranscribeEntryWorker.new()
        |> Oban.insert!()

      Logger.info("EnqueueTranscription job enqueued", oban_job_id: job.id, entry_id: entry.id)

      {:ok, entry}
    end)
  end
end
