defmodule SitevoiceWeb.LogChannel do
  use Phoenix.Channel

  alias Sitevoice.Reporting.DailyLog

  @impl true
  def join("log:" <> log_id, _params, socket) do
    org_id = socket.assigns.current_user.organization_id

    case Ash.get(DailyLog, log_id, tenant: to_string(org_id), authorize?: false) do
      {:ok, _log} ->
        topic = "org:#{org_id}:log:#{log_id}"
        Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
        {:ok, assign(socket, log_id: log_id, organization_id: org_id)}

      {:error, _} ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info({:report_ready, payload}, socket) do
    push(socket, "report_ready", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_update, payload}, socket) do
    push(socket, "pipeline_update", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_failed, payload}, socket) do
    push(socket, "pipeline_failed", payload)
    {:noreply, socket}
  end
end
