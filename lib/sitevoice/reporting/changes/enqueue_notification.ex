defmodule Sitevoice.Reporting.Changes.EnqueueNotification do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _cs, log ->
      %{log_id: log.id, organization_id: log.organization_id}
      |> Sitevoice.Workers.NotifyPmWorker.new()
      |> Oban.insert()

      {:ok, log}
    end)
  end
end
