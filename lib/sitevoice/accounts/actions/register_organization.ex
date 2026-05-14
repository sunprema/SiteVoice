defmodule Sitevoice.Accounts.Actions.RegisterOrganization do
  @moduledoc false

  def call(%{org_name: org_name, user_email: user_email, user_password: user_password, user_name: user_name}) do
    Ash.transact(
      [Sitevoice.Accounts.Organization, Sitevoice.Accounts.User],
      fn ->
        with {:ok, org} <-
               Sitevoice.Accounts.Organization
               |> Ash.Changeset.for_create(:register, %{name: org_name})
               |> Ash.create(authorize?: false),
             {:ok, user} <-
               Sitevoice.Accounts.User
               |> Ash.Changeset.for_create(:register_with_password, %{
                 email: user_email,
                 password: user_password,
                 password_confirmation: user_password,
                 organization_id: org.id,
                 role: :org_admin,
                 name: user_name
               })
               |> Ash.create(authorize?: false, tenant: to_string(org.id)) do
          %{organization: org, user: user, token: user.__metadata__[:token]}
        end
      end
    )
  end
end
