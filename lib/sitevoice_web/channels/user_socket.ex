defmodule SitevoiceWeb.UserSocket do
  use Phoenix.Socket

  channel "recording:*", SitevoiceWeb.RecordingChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case AshAuthentication.Jwt.verify(token, :sitevoice) do
      {:ok, claims, resource} ->
        case AshAuthentication.subject_to_user(claims["sub"], resource) do
          {:ok, user} ->
            {:ok, assign(socket, :current_user, user)}

          {:error, _} ->
            :error
        end

      :error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
