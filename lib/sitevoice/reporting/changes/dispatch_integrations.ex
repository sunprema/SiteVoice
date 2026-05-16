defmodule Sitevoice.Reporting.Changes.DispatchIntegrations do
  use Ash.Resource.Change

  require Ash.Query

  alias Sitevoice.Integrations.Integration
  alias Sitevoice.Workers.DispatchIntegrationWorker

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      org_id = to_string(log.organization_id)

      integrations =
        Integration
        |> Ash.Query.filter(active == true)
        |> Ash.read!(authorize?: false, tenant: org_id)

      Enum.each(integrations, fn integration ->
        %{
          "log_id" => to_string(log.id),
          "integration_id" => to_string(integration.id),
          "organization_id" => org_id
        }
        |> DispatchIntegrationWorker.new()
        |> Oban.insert!()
      end)

      {:ok, log}
    end)
  end
end
