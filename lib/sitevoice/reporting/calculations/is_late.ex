defmodule Sitevoice.Reporting.Calculations.IsLate do
  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context) do
    {:ok,
     Enum.map(records, fn record ->
       case record.submitted_at do
         nil -> false
         submitted_at -> DateTime.to_time(submitted_at).hour >= 18
       end
     end)}
  end
end
