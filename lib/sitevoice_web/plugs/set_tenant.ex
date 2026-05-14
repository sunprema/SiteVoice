defmodule SitevoiceWeb.Plugs.SetTenant do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn

      user ->
        Ash.PlugHelpers.set_tenant(conn, to_string(user.organization_id))
    end
  end
end
