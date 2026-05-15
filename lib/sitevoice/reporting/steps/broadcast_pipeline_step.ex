defmodule Sitevoice.Steps.BroadcastPipelineStep do
  use Reactor.Step

  require Logger

  def run(%{step: step_name, log_id: log_id, organization_id: org_id}, _, _) do
    topic = "org:#{org_id}:log:#{log_id}"
    Logger.info("Pipeline step broadcast", step: step_name, topic: topic)

    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      topic,
      {:pipeline_update, %{step: step_name, status: :complete}}
    )

    :telemetry.execute([:sitevoice, :pipeline, :step_complete], %{}, %{
      step: step_name,
      log_id: log_id,
      org_id: org_id
    })

    {:ok, :sent}
  end

  def compensate(_, _, _, _), do: :ok
end
