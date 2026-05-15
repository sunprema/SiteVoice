defmodule SitevoiceWeb.RecordingChannel do
  use Phoenix.Channel

  require Logger

  alias Sitevoice.Reporting.DailyLog

  @impl true
  def join("recording:" <> log_id, _params, socket) do
    user = socket.assigns.current_user
    org_id = user.organization_id

    Logger.info("RecordingChannel join attempt",
      log_id: log_id,
      user_id: user.id,
      org_id: org_id
    )

    if authorized?(socket, log_id) do
      topic = "org:#{org_id}:log:#{log_id}"
      Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
      Logger.info("RecordingChannel joined successfully", log_id: log_id, topic: topic)
      {:ok, assign(socket, log_id: log_id, organization_id: org_id)}
    else
      Logger.warning("RecordingChannel join rejected: not authorized",
        log_id: log_id,
        user_id: user.id,
        org_id: org_id
      )

      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("recording_complete", %{"log_id" => log_id}, socket) do
    org_id = socket.assigns.organization_id
    Logger.info("RecordingChannel received recording_complete, enqueuing processing", log_id: log_id, org_id: org_id)

    case %{log_id: log_id, organization_id: org_id}
         |> Sitevoice.Workers.AudioProcessor.new()
         |> Oban.insert() do
      {:ok, job} ->
        Logger.info("RecordingChannel enqueued AudioProcessor job", log_id: log_id, oban_job_id: job.id)

      {:error, reason} ->
        Logger.error("RecordingChannel failed to enqueue AudioProcessor job",
          log_id: log_id,
          reason: inspect(reason)
        )
    end

    push(socket, "processing_started", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:report_ready, payload}, socket) do
    Logger.info("RecordingChannel pushing report_ready to client", log_id: socket.assigns[:log_id])
    push(socket, "report_ready", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_update, %{step: step} = payload}, socket) do
    Logger.debug("RecordingChannel pushing pipeline_update", step: step, log_id: socket.assigns[:log_id])
    push(socket, "pipeline_update", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_failed, payload}, socket) do
    Logger.warning("RecordingChannel pushing pipeline_failed to client", log_id: socket.assigns[:log_id])
    push(socket, "pipeline_failed", payload)
    {:noreply, socket}
  end

  defp authorized?(socket, log_id) do
    org_id = socket.assigns.current_user.organization_id
    user_id = socket.assigns.current_user.id

    case Ash.get(DailyLog, log_id, tenant: to_string(org_id), authorize?: false) do
      {:ok, log} ->
        log.foreman_id == user_id

      {:error, reason} ->
        Logger.warning("RecordingChannel authorization check failed",
          log_id: log_id,
          reason: inspect(reason)
        )

        false
    end
  end
end
