defmodule Sitevoice.Reporting.Calculations.AudioUrl do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:audio_key]

  @impl true
  def calculate(records, _opts, _context) do
    {:ok,
     Enum.map(records, fn record ->
       case record.audio_key do
         nil -> nil
         key -> {:ok, url} = Sitevoice.Storage.presigned_url("sitevoice-audio", key, 3600); url
       end
     end)}
  end
end
