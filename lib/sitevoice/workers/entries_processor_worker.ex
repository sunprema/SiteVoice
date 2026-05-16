defmodule Sitevoice.Workers.EntriesProcessorWorker do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        attempt: attempt,
        args: %{"log_id" => log_id, "organization_id" => org_id}
      }) do
    Logger.metadata(log_id: log_id, org_id: org_id, oban_job_id: job_id, attempt: attempt)
    Logger.info("EntriesProcessorWorker starting pipeline")

    result =
      :telemetry.span([:sitevoice, :pipeline], %{log_id: log_id, org_id: org_id}, fn ->
        {Reactor.run(Sitevoice.Reporting.Reactors.ProcessLogEntries, %{
           log_id: log_id,
           organization_id: org_id
         }), %{}}
      end)

    case result do
      {:ok, _} ->
        Logger.info("EntriesProcessorWorker pipeline completed")
        :ok

      {:error, reason} ->
        error_summary = format_pipeline_error(reason)
        Logger.error("EntriesProcessorWorker pipeline failed: #{error_summary}")
        mark_failed(log_id, org_id, reason)
        {:error, reason}
    end
  end

  defp mark_failed(log_id, org_id, reason) do
    Logger.warning("EntriesProcessorWorker marking log as failed: #{format_pipeline_error(reason)}")

    case Ash.get(Sitevoice.Reporting.DailyLog, log_id, authorize?: false, tenant: org_id) do
      {:ok, log} ->
        Ash.update!(log, %{}, action: :mark_failed, authorize?: false, tenant: org_id)

      {:error, fetch_err} ->
        Logger.error("EntriesProcessorWorker could not fetch log to mark failed: #{inspect(fetch_err)}")
    end
  end

  defp format_pipeline_error(errors) when is_list(errors) do
    Enum.map_join(errors, "; ", &format_one_error/1)
  end

  defp format_pipeline_error(error), do: format_one_error(error)

  defp format_one_error(%{step: step, errors: errs}) when is_list(errs) do
    "step=#{inspect(step)} errors=[#{Enum.map_join(errs, ", ", &format_one_error/1)}]"
  end

  defp format_one_error(%{message: msg}), do: msg
  defp format_one_error(%{reason: r}), do: inspect(r)
  defp format_one_error(e) when is_exception(e), do: Exception.message(e)
  defp format_one_error(e), do: inspect(e)
end
