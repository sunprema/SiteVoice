defmodule Sitevoice.Steps.GeneratePdf do
  use Reactor.Step

  # Implemented in Slice 05 when Imprintor integration exists
  def run(%{log: _log}, _, _), do: {:ok, <<>>}

  def compensate(_, _, _, _), do: :ok
end
