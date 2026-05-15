defmodule Sitevoice.Steps.FetchLog do
  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id}, _, _) do
    Logger.debug("FetchLog loading daily log", log_id: log_id, org_id: org_id)

    result =
      Ash.get(Sitevoice.Reporting.DailyLog, log_id,
        load: [:organization, :project, :foreman, :photos],
        authorize?: false,
        tenant: org_id
      )

    case result do
      {:ok, log} ->
        Logger.info("FetchLog loaded log",
          log_id: log_id,
          status: log.status,
          audio_key: log.audio_key,
          photo_count: length(log.photos)
        )

      {:error, reason} ->
        Logger.error("FetchLog failed to load log",
          log_id: log_id,
          org_id: org_id,
          reason: inspect(reason)
        )
    end

    result
  end

  def compensate(_, _, _, _), do: :ok
end
