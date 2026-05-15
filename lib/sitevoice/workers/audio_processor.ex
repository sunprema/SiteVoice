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

    start_time = System.monotonic_time(:millisecond)

    :telemetry.execute([:sitevoice, :pipeline, :start], %{}, %{log_id: log_id, org_id: org_id})

    result =
      Reactor.run(Sitevoice.Reporting.Reactors.ProcessRecording, %{
        log_id: log_id,
        organization_id: org_id
      })

    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        :telemetry.execute([:sitevoice, :pipeline, :stop], %{duration_ms: elapsed_ms}, %{
          log_id: log_id,
          org_id: org_id
        })

        Logger.info("AudioProcessor pipeline completed", duration_ms: elapsed_ms)
        :ok

      {:error, reason} ->
        :telemetry.execute([:sitevoice, :pipeline, :exception], %{duration_ms: elapsed_ms}, %{
          log_id: log_id,
          org_id: org_id,
          reason: inspect(reason)
        })

        Logger.error("AudioProcessor pipeline failed",
          reason: inspect(reason),
          duration_ms: elapsed_ms
        )

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
