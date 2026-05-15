defmodule SitevoiceWeb.RecordingChannel do
  use Phoenix.Channel

  alias Sitevoice.Reporting.DailyLog

  @impl true
  def join("recording:" <> log_id, _params, socket) do
    org_id = socket.assigns.current_user.organization_id

    if authorized?(socket, log_id) do
      topic = "org:#{org_id}:log:#{log_id}"
      Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
      {:ok, assign(socket, log_id: log_id, organization_id: org_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("recording_complete", %{"log_id" => log_id}, socket) do
    org_id = socket.assigns.organization_id

    %{log_id: log_id, organization_id: org_id}
    |> Sitevoice.Workers.AudioProcessor.new()
    |> Oban.insert()

    push(socket, "processing_started", %{})
    {:noreply, socket}
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

  defp authorized?(socket, log_id) do
    org_id = socket.assigns.current_user.organization_id
    user_id = socket.assigns.current_user.id

    case Ash.get(DailyLog, log_id,
           tenant: to_string(org_id),
           authorize?: false
         ) do
      {:ok, log} -> log.foreman_id == user_id
      _ -> false
    end
  end
end
