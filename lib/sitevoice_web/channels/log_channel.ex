defmodule SitevoiceWeb.LogChannel do
  use Phoenix.Channel

  require Logger

  alias Sitevoice.Reporting.DailyLog

  @impl true
  def join("log:" <> log_id, _params, socket) do
    user = socket.assigns.current_user
    org_id = user.organization_id

    Logger.info("LogChannel join attempt",
      log_id: log_id,
      user_id: user.id,
      org_id: org_id
    )

    case Ash.get(DailyLog, log_id, tenant: to_string(org_id), authorize?: false) do
      {:ok, log} ->
        topic = "org:#{org_id}:log:#{log_id}"
        Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)

        Logger.info("LogChannel joined successfully",
          log_id: log_id,
          log_status: log.status,
          topic: topic
        )

        {:ok, assign(socket, log_id: log_id, organization_id: org_id)}

      {:error, reason} ->
        Logger.warning("LogChannel join rejected: log not found",
          log_id: log_id,
          org_id: org_id,
          reason: inspect(reason)
        )

        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info({:report_ready, payload}, socket) do
    Logger.info("LogChannel pushing report_ready to client", log_id: socket.assigns[:log_id])
    push(socket, "report_ready", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_update, %{step: step} = payload}, socket) do
    Logger.debug("LogChannel pushing pipeline_update", step: step, log_id: socket.assigns[:log_id])
    push(socket, "pipeline_update", payload)
    {:noreply, socket}
  end

  def handle_info({:pipeline_failed, payload}, socket) do
    Logger.warning("LogChannel pushing pipeline_failed to client",
      log_id: socket.assigns[:log_id]
    )

    push(socket, "pipeline_failed", payload)
    {:noreply, socket}
  end
end
