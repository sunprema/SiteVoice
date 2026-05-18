defmodule Sitevoice.Reporting.Changes.EnqueueClarification do
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      Logger.info("EnqueueClarification enqueuing ClarificationProcessor job",
        log_id: log.id,
        org_id: log.organization_id
      )

      job =
        %{log_id: log.id, organization_id: log.organization_id}
        |> Sitevoice.Workers.ClarificationProcessor.new()
        |> Oban.insert!()

      Logger.info("EnqueueClarification job enqueued",
        oban_job_id: job.id,
        log_id: log.id
      )

      {:ok, log}
    end)
  end
end
