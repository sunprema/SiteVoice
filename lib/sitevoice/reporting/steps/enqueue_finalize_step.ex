defmodule Sitevoice.Steps.EnqueueFinalizeStep do
  @moduledoc """
  Inside-a-reactor step that enqueues `Sitevoice.Workers.FinalizeReportWorker`
  for the given log. Used by `ProcessRecording` and `ProcessClarification`
  reactors to hand off PDF generation as a separate Oban job.
  """

  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id}, _, _) do
    job =
      %{log_id: log_id, organization_id: org_id}
      |> Sitevoice.Workers.FinalizeReportWorker.new()
      |> Oban.insert!()

    Logger.info("EnqueueFinalizeStep enqueued FinalizeReportWorker",
      log_id: log_id,
      oban_job_id: job.id
    )

    {:ok, job.id}
  end

  def compensate(_, _, _, _), do: :ok
end
