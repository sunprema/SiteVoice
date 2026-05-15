defmodule Sitevoice.Workers.AudioProcessor do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        attempt: attempt,
        args: %{"log_id" => log_id, "organization_id" => org_id}
      }) do
    Logger.metadata(log_id: log_id, org_id: org_id, oban_job_id: job_id, attempt: attempt)
    Logger.info("AudioProcessor starting pipeline", log_id: log_id, org_id: org_id, attempt: attempt)

    result =
      :telemetry.span([:sitevoice, :pipeline], %{log_id: log_id, org_id: org_id}, fn ->
        {Reactor.run(Sitevoice.Reporting.Reactors.ProcessRecording, %{
           log_id: log_id,
           organization_id: org_id
         }), %{}}
      end)

    case result do
      {:ok, _} ->
        Logger.info("AudioProcessor pipeline completed")
        :ok

      {:error, reason} ->
        Logger.error("AudioProcessor pipeline failed", reason: inspect(reason))
        mark_failed(log_id, org_id, reason)
        {:error, reason}
    end
  end

  defp mark_failed(log_id, org_id, reason) do
    Logger.warning("AudioProcessor marking log as failed", reason: inspect(reason))

    case Ash.get(Sitevoice.Reporting.DailyLog, log_id, authorize?: false, tenant: org_id) do
      {:ok, log} ->
        Ash.update!(log, %{}, action: :mark_failed, authorize?: false, tenant: org_id)
        Logger.info("AudioProcessor log marked as failed in database")

      {:error, fetch_err} ->
        Logger.error("AudioProcessor could not fetch log to mark as failed",
          fetch_error: inspect(fetch_err)
        )
    end
  end
end
