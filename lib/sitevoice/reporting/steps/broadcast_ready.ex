defmodule Sitevoice.Steps.BroadcastReady do
  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id, pdf_url: url}, _, _) do
    topic = "org:#{org_id}:log:#{log_id}"
    has_url = not is_nil(url)
    Logger.info("Broadcasting report_ready", log_id: log_id, topic: topic, has_pdf_url: has_url)

    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      topic,
      {:report_ready, %{log_id: log_id, pdf_url: url}}
    )

    :telemetry.execute([:sitevoice, :pipeline, :report_ready], %{}, %{
      log_id: log_id,
      org_id: org_id,
      has_pdf_url: has_url
    })

    {:ok, :sent}
  end

  def compensate(_, _, _, _), do: :ok
end
