defmodule Sitevoice.Reporting.Changes.DispatchIntegrations do
  # Implemented in Slice 08 when Integrations domain exists
  use Ash.Resource.Change

  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      {:ok, log}
    end)
  end
end
