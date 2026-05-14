defmodule Sitevoice.Workers.AudioProcessor do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}) do
    Logger.info("AudioProcessor: processing log #{log_id} for org #{org_id}")

    case Reactor.run(Sitevoice.Reporting.Reactors.ProcessRecording, %{
           log_id: log_id,
           organization_id: org_id
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        mark_failed(log_id, org_id, reason)
        {:error, reason}
    end
  end

  defp mark_failed(log_id, org_id, reason) do
    Logger.error("AudioProcessor: pipeline failed for log #{log_id}: #{inspect(reason)}")

    case Ash.get(Sitevoice.Reporting.DailyLog, log_id,
           authorize?: false,
           tenant: org_id
         ) do
      {:ok, log} ->
        Ash.update!(log, %{}, action: :mark_failed, authorize?: false, tenant: org_id)

      {:error, _} ->
        :ok
    end
  end
end
