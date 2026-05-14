defmodule Sitevoice.Reporting.Changes.EnqueueProcessing do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      %{log_id: log.id, organization_id: log.organization_id}
      |> Sitevoice.Workers.AudioProcessor.new()
      |> Oban.insert!()

      {:ok, log}
    end)
  end
end
