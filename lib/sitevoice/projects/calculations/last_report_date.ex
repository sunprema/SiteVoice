defmodule Sitevoice.Projects.Calculations.LastReportDate do
  # Implemented in Slice 03 when DailyLog exists
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    {:ok, Enum.map(records, fn _ -> nil end)}
  end
end
