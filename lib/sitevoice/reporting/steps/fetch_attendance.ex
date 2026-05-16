defmodule Sitevoice.Steps.FetchAttendance do
  use Reactor.Step

  require Logger

  def run(%{log_id: log_id, organization_id: org_id}, _, _) do
    Logger.debug("FetchAttendance loading attendance rows", log_id: log_id)

    result =
      Ash.read(Sitevoice.Reporting.DailyAttendance,
        action: :list_for_log,
        arguments: %{daily_log_id: log_id},
        authorize?: false,
        tenant: org_id
      )

    case result do
      {:ok, rows} ->
        Logger.info("FetchAttendance loaded #{length(rows)} rows", log_id: log_id)

      {:error, reason} ->
        Logger.warning("FetchAttendance failed, using empty list: #{inspect(reason)}")
    end

    case result do
      {:ok, rows} -> {:ok, rows}
      {:error, _} -> {:ok, []}
    end
  end

  def compensate(_, _, _, _), do: :ok
end
