defmodule Sitevoice.Accounts.Changes.GenerateSlug do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument_or_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        slug = slugify(name)
        Ash.Changeset.force_change_attribute(changeset, :slug, slug)
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
