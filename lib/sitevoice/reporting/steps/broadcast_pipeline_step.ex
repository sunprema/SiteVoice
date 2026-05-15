defmodule Sitevoice.Steps.BroadcastPipelineStep do
  use Reactor.Step

  def run(%{step: step_name, log_id: log_id, organization_id: org_id}, _, _) do
    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      "org:#{org_id}:log:#{log_id}",
      {:pipeline_update, %{step: step_name, status: :complete}}
    )

    {:ok, :sent}
  end

  def compensate(_, _, _, _), do: :ok
end
