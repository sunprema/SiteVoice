defmodule Sitevoice.Steps.BroadcastReady do
  use Reactor.Step

  def run(%{log_id: log_id, organization_id: org_id, pdf_url: url}, _, _) do
    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      "org:#{org_id}:log:#{log_id}",
      {:report_ready, %{log_id: log_id, pdf_url: url}}
    )

    {:ok, :sent}
  end

  def compensate(_, _, _, _), do: :ok
end
