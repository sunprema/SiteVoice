defmodule SitevoiceWeb.Plugs.VerifyToken do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"errors":[{"code":"unauthorized","detail":"Authentication required"}]}))
        |> halt()

      _user ->
        conn
    end
  end
end
