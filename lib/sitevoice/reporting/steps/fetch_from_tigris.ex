defmodule Sitevoice.Steps.FetchFromTigris do
  use Reactor.Step

  require Logger

  def run(%{key: key}, _, _) do
    Logger.debug("FetchFromTigris fetching object", storage_key: key)

    result = Sitevoice.Storage.fetch(key)

    case result do
      {:ok, binary} ->
        Logger.info("FetchFromTigris fetch succeeded",
          storage_key: key,
          bytes: byte_size(binary)
        )

      {:error, reason} ->
        Logger.error("FetchFromTigris fetch failed",
          storage_key: key,
          reason: inspect(reason)
        )
    end

    result
  end

  def compensate(_, _, _, _), do: :ok
end
