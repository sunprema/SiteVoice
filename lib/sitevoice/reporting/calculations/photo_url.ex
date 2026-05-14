defmodule Sitevoice.Reporting.Calculations.PhotoUrl do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    {:ok,
     Enum.map(records, fn record ->
       case record.storage_key do
         nil -> nil
         key -> {:ok, url} = Sitevoice.Storage.presigned_url("sitevoice-photos", key, 3600); url
       end
     end)}
  end
end
