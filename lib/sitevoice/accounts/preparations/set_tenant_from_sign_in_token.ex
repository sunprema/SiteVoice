defmodule Sitevoice.Accounts.Preparations.SetTenantFromSignInToken do
  @moduledoc false
  # Peeks at the short-lived sign-in token (no signature validation) to extract
  # the "tenant" claim, then sets it on the query so that the subsequent
  # SignInWithTokenPreparation validates the JWT with the correct expected tenant.
  # Without this, the tenant claim in the JWT (org_id) is compared against nil
  # (no tenant in the unauthenticated request context), causing sign-in to fail.

  use Ash.Resource.Preparation
  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    with token when is_binary(token) <- Ash.Query.get_argument(query, :token),
         {:ok, %{"tenant" => tenant}} when is_binary(tenant) <-
           AshAuthentication.Jwt.peek(token) do
      Ash.Query.set_tenant(query, tenant)
    else
      _ -> query
    end
  end
end
