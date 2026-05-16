defmodule Sitevoice.Reporting.Calculations.EntryPhotoUrl do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:photo_key]

  @impl true
  def calculate(records, _opts, _context) do
    {:ok,
     Enum.map(records, fn record ->
       case record.photo_key do
         nil ->
           nil

         key ->
           {:ok, url} = Sitevoice.Storage.presigned_url("sitevoice-photos", key, 3600)
           url
       end
     end)}
  end
end
