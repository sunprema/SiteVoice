defmodule SitevoiceWeb.AshTypescriptRpcController do
  use SitevoiceWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:sitevoice, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:sitevoice, conn, params)
    json(conn, result)
  end
end
