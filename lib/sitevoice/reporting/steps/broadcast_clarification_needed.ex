defmodule Sitevoice.Steps.BroadcastClarificationNeeded do
  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id, questions: questions}, _, _) do
    topic = "org:#{org_id}:log:#{log_id}"

    Logger.info("Broadcasting clarification_needed",
      log_id: log_id,
      topic: topic,
      question_count: length(questions)
    )

    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      topic,
      {:clarification_needed, %{log_id: log_id, questions: questions}}
    )

    :telemetry.execute([:sitevoice, :pipeline, :clarification_needed], %{}, %{
      log_id: log_id,
      org_id: org_id,
      question_count: length(questions)
    })

    {:ok, :sent}
  end

  def compensate(_, _, _, _), do: :ok
end
