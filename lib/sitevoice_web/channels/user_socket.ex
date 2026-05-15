defmodule SitevoiceWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  channel "recording:*", SitevoiceWeb.RecordingChannel
  channel "log:*", SitevoiceWeb.LogChannel

  @impl true
  def connect(%{"token" => token}, socket, connect_info) do
    remote_ip = get_in(connect_info, [:peer_data, :address]) |> format_ip()

    with {:ok, %{"tenant" => tenant}} <- AshAuthentication.Jwt.peek(token),
         {:ok, claims, resource} <-
           AshAuthentication.Jwt.verify(token, :sitevoice, tenant: tenant),
         {:ok, user} <- AshAuthentication.subject_to_user(claims["sub"], resource) do
      Logger.info("WebSocket connected",
        user_id: user.id,
        org_id: user.organization_id,
        remote_ip: remote_ip
      )

      {:ok, assign(socket, :current_user, user)}
    else
      error ->
        Logger.warning("WebSocket connection rejected", reason: inspect(error), remote_ip: remote_ip)
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.warning("WebSocket connection rejected: missing token")
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"

  defp format_ip(nil), do: "unknown"
  defp format_ip(ip) when is_tuple(ip), do: ip |> Tuple.to_list() |> Enum.join(".")
  defp format_ip(ip), do: inspect(ip)
end
