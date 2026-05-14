defmodule Sitevoice.Steps.FetchLog do
  use Reactor.Step

  def run(%{log_id: log_id, organization_id: org_id}, _, _) do
    Ash.get(Sitevoice.Reporting.DailyLog, log_id,
      load: [:organization, :project, :foreman, :photos],
      authorize?: false,
      tenant: org_id
    )
  end

  def compensate(_, _, _, _), do: :ok
end
