defmodule Sitevoice.Accounts.Changes.HashPassword do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    raw =
      case Ash.Changeset.get_argument(changeset, :password) do
        nil -> :crypto.strong_rand_bytes(32) |> Base.encode64()
        password -> password
      end

    hash = Bcrypt.hash_pwd_salt(raw)
    Ash.Changeset.force_change_attribute(changeset, :hashed_password, hash)
  end
end
