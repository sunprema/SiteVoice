defmodule Sitevoice.Accounts.Preparations.SetTenantMetadata do
  @moduledoc false

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn _query, users ->
      {:ok, Enum.map(users, &Ash.Resource.put_metadata(&1, :tenant, to_string(&1.organization_id)))}
    end)
  end
end
