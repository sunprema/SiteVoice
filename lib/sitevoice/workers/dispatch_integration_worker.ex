defmodule Sitevoice.Workers.DispatchIntegrationWorker do
  use Oban.Worker, queue: :integrations, max_attempts: 3

  require Logger

  alias Sitevoice.Integrations.Integration
  alias Sitevoice.Integrations.IntegrationEvent
  alias Sitevoice.Reporting.DailyLog

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "log_id" => log_id,
          "integration_id" => integration_id,
          "organization_id" => org_id
        }
      }) do
    Logger.metadata(log_id: log_id, integration_id: integration_id, org_id: org_id)
    Logger.info("DispatchIntegrationWorker starting")

    integration = Ash.get!(Integration, integration_id, authorize?: false, tenant: org_id)

    log =
      Ash.get!(DailyLog, log_id,
        authorize?: false,
        tenant: org_id,
        load: [:project, :foreman]
      )

    payload = build_payload(log)

    case post_to_procore(payload, integration) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        record_event(org_id, integration_id, log_id, :sent, payload, %{
          status: response.status,
          body: response.body
        })

        Logger.info("DispatchIntegrationWorker succeeded", integration_id: integration_id)
        :ok

      {:ok, %{status: status, body: body}} ->
        reason = "HTTP #{status}: #{inspect(body)}"

        Logger.error("DispatchIntegrationWorker failed",
          integration_id: integration_id,
          reason: reason
        )

        record_event(org_id, integration_id, log_id, :failed, payload, %{
          status: status,
          error: reason
        })

        {:error, reason}

      {:error, reason} ->
        Logger.error("DispatchIntegrationWorker failed",
          integration_id: integration_id,
          reason: inspect(reason)
        )

        record_event(org_id, integration_id, log_id, :failed, payload, %{
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp build_payload(log) do
    foreman_name =
      if log.foreman, do: log.foreman.name, else: "Unknown"

    project_name =
      if log.project, do: log.project.name, else: "Unknown"

    %{
      daily_log: %{
        log_date: Date.to_string(log.date),
        notes: format_notes(log),
        status: "approved",
        created_by: foreman_name,
        project: project_name
      }
    }
  end

  defp format_notes(log) do
    parts = []

    parts =
      if log.progress && log.progress != "",
        do: ["Progress: #{log.progress}" | parts],
        else: parts

    parts =
      if log.weather && log.weather != "",
        do: ["Weather: #{log.weather}" | parts],
        else: parts

    parts =
      if log.delays && log.delays != "",
        do: ["Delays: #{log.delays}" | parts],
        else: parts

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp post_to_procore(payload, integration) do
    config = integration.config
    base_url = Map.get(config, "base_url", "https://api.procore.com")
    project_id = Map.get(config, "project_id", "")
    access_token = Map.get(config, "access_token", "")

    url = "#{base_url}/rest/v1.0/projects/#{project_id}/daily_logs"

    req_options = Application.get_env(:sitevoice, :procore_req_options, [])

    Req.post(
      url,
      [
        headers: [{"Authorization", "Bearer #{access_token}"}],
        json: payload,
        receive_timeout: 30_000
      ] ++ req_options
    )
  end

  defp record_event(org_id, integration_id, log_id, status, payload, response) do
    IntegrationEvent
    |> Ash.Changeset.for_create(
      :create,
      %{
        organization_id: org_id,
        integration_id: integration_id,
        log_id: log_id,
        status: status,
        payload: payload,
        response: response
      },
      authorize?: false,
      tenant: org_id
    )
    |> Ash.create!()
  end
end
