defmodule Sitevoice.Workers.ClarificationProcessor do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        attempt: attempt,
        args: %{"log_id" => log_id, "organization_id" => org_id}
      }) do
    Logger.metadata(log_id: log_id, org_id: org_id, oban_job_id: job_id, attempt: attempt)
    Logger.info("ClarificationProcessor starting", log_id: log_id, org_id: org_id, attempt: attempt)

    result =
      :telemetry.span([:sitevoice, :clarification], %{log_id: log_id, org_id: org_id}, fn ->
        {Reactor.run(Sitevoice.Reporting.Reactors.ProcessClarification, %{
           log_id: log_id,
           organization_id: org_id
         }), %{}}
      end)

    case result do
      {:ok, _} ->
        Logger.info("ClarificationProcessor completed")
        :ok

      {:error, reason} ->
        Logger.error("ClarificationProcessor failed: #{inspect(reason)}")
        mark_failed(log_id, org_id)
        {:error, reason}
    end
  end

  defp mark_failed(log_id, org_id) do
    case Ash.get(Sitevoice.Reporting.DailyLog, log_id, authorize?: false, tenant: org_id) do
      {:ok, log} ->
        Ash.update!(log, %{}, action: :mark_failed, authorize?: false, tenant: org_id)

        Phoenix.PubSub.broadcast(
          Sitevoice.PubSub,
          "org:#{org_id}:log:#{log_id}",
          {:pipeline_failed, %{log_id: log_id, stage: :clarification}}
        )

      {:error, fetch_err} ->
        Logger.error("ClarificationProcessor could not fetch log to mark as failed: #{inspect(fetch_err)}")
    end
  end
end
