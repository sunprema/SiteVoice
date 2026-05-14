defmodule Sitevoice.Projects.Changes.NormalizeCode do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :code) do
      nil ->
        changeset

      code ->
        normalized = code |> String.trim() |> String.upcase()
        Ash.Changeset.change_attribute(changeset, :code, normalized)
    end
  end
end
