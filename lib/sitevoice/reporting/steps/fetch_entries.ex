defmodule Sitevoice.Steps.FetchEntries do
  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id}, _, _) do
    Logger.debug("FetchEntries loading log entries", log_id: log_id, org_id: org_id)

    result =
      Ash.read(Sitevoice.Reporting.LogEntry,
        action: :for_log,
        arguments: %{daily_log_id: log_id},
        authorize?: false,
        tenant: org_id
      )

    case result do
      {:ok, entries} ->
        counts = Enum.frequencies_by(entries, & &1.type)

        Logger.info("FetchEntries loaded entries",
          log_id: log_id,
          total: length(entries),
          voice_memos: Map.get(counts, :voice_memo, 0),
          text_notes: Map.get(counts, :text_note, 0),
          photos: Map.get(counts, :photo, 0)
        )

      {:error, reason} ->
        Logger.error("FetchEntries failed", log_id: log_id, reason: inspect(reason))
    end

    result
  end

  def compensate(_, _, _, _), do: :ok
end
