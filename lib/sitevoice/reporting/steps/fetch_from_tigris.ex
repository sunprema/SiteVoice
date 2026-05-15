defmodule Sitevoice.Steps.FetchFromTigris do
  use Reactor.Step

  require Logger

  def run(%{key: key}, _, _) do
    Logger.debug("FetchFromTigris fetching object", storage_key: key)

    case Sitevoice.Storage.fetch(key) do
      {:ok, binary} = ok ->
        Logger.info("FetchFromTigris fetch succeeded", storage_key: key, bytes: byte_size(binary))
        ok

      error ->
        # Storage.fetch already logs the error with bucket/key detail
        error
    end
  end

  def compensate(_, _, _, _), do: :ok
end
