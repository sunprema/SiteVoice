defmodule Sitevoice.Steps.SetTenant do
  use Reactor.Step

  def run(%{organization_id: org_id}, _, _) do
    {:ok, org_id}
  end

  def compensate(_, _, _, _), do: :ok
end
