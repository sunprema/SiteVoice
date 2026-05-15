defmodule SitevoiceWeb.Plugs.SetTenantFromToken do
  @moduledoc false
  # Extracts the tenant from the session JWT (without verifying signature)
  # so that load_from_session can validate the tenant claim correctly.

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with token when is_binary(token) <- Plug.Conn.get_session(conn, "user_token"),
         {:ok, %{"tenant" => tenant}} when is_binary(tenant) <-
           AshAuthentication.Jwt.peek(token) do
      Ash.PlugHelpers.set_tenant(conn, tenant)
    else
      _ -> conn
    end
  end
end
