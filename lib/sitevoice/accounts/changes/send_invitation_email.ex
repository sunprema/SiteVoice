defmodule Sitevoice.Accounts.Changes.SendInvitationEmail do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      Ash.ActionInput.for_action(
        Sitevoice.Accounts.User,
        :request_password_reset_token,
        %{email: user.email},
        authorize?: false,
        tenant: to_string(user.organization_id)
      )
      |> Ash.run_action!()

      {:ok, user}
    end)
  end
end
