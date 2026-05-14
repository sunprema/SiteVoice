defmodule Sitevoice.Steps.FetchFromTigris do
  use Reactor.Step

  def run(%{key: key}, _, _) do
    Sitevoice.Storage.fetch(key)
  end

  def compensate(_, _, _, _), do: :ok
end
