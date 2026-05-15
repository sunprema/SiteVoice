defmodule SitevoiceWeb.UserSocket do
  use Phoenix.Socket

  channel "recording:*", SitevoiceWeb.RecordingChannel
  channel "log:*", SitevoiceWeb.LogChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, %{"tenant" => tenant}} <- AshAuthentication.Jwt.peek(token),
         {:ok, claims, resource} <- AshAuthentication.Jwt.verify(token, :sitevoice, tenant: tenant),
         {:ok, user} <- AshAuthentication.subject_to_user(claims["sub"], resource) do
      {:ok, assign(socket, :current_user, user)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
