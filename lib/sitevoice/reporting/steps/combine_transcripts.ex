defmodule Sitevoice.Steps.CombineTranscripts do
  use Reactor.Step

  require Logger

  def run(%{entries: entries}, _, _) do
    combined =
      entries
      |> Enum.filter(&(&1.type in [:voice_memo, :text_note]))
      |> Enum.map(fn
        %{type: :voice_memo, transcript: t} when is_binary(t) -> t
        %{type: :text_note, text: t} when is_binary(t) -> t
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    Logger.info("CombineTranscripts combined #{String.length(combined)} chars from #{length(entries)} entries")

    {:ok, combined}
  end

  def compensate(_, _, _, _), do: :ok
end
