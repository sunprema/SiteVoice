defmodule Sitevoice.Accounts.UserTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :auth

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User

  defp create_org_with_admin(opts \\ []) do
    org_name = Keyword.get(opts, :org_name, "Test Org #{System.unique_integer()}")
    email = Keyword.get(opts, :email, "admin#{System.unique_integer()}@example.com")

    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: org_name,
        user_email: email,
        user_password: "password123",
        user_name: "Admin User"
      })

    result
  end

  describe "invite action" do
    test "creates user in same org as actor" do
      %{organization: org, user: admin} = create_org_with_admin()

      assert {:ok, invited} =
               User
               |> Ash.Changeset.for_create(
                 :invite,
                 %{email: "worker@example.com", name: "Worker", role: :foreman},
                 actor: admin,
                 tenant: to_string(org.id)
               )
               |> Ash.create()

      assert invited.organization_id == org.id
      assert invited.role == :foreman
    end

    test "is rejected for non-org_admin actor" do
      %{organization: org, user: admin} = create_org_with_admin()

      {:ok, foreman} =
        User
        |> Ash.Changeset.for_create(
          :invite,
          %{email: "foreman@example.com", name: "Foreman", role: :foreman},
          actor: admin,
          tenant: to_string(org.id)
        )
        |> Ash.create()

      assert {:error, %Ash.Error.Forbidden{}} =
               User
               |> Ash.Changeset.for_create(
                 :invite,
                 %{email: "another@example.com", name: "Another", role: :foreman},
                 actor: foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.create()
    end
  end

  describe "update_profile action" do
    test "is rejected when actor is a different user" do
      %{organization: org, user: admin} = create_org_with_admin()

      {:ok, other} =
        User
        |> Ash.Changeset.for_create(
          :invite,
          %{email: "other@example.com", name: "Other"},
          actor: admin,
          tenant: to_string(org.id)
        )
        |> Ash.create()

      assert {:error, %Ash.Error.Forbidden{}} =
               other
               |> Ash.Changeset.for_update(:update_profile, %{name: "Hacked"},
                 actor: admin,
                 tenant: to_string(org.id)
               )
               |> Ash.update()
    end
  end

  describe "update_role action" do
    test "is rejected for non-org_admin" do
      %{organization: org, user: admin} = create_org_with_admin()

      {:ok, foreman} =
        User
        |> Ash.Changeset.for_create(
          :invite,
          %{email: "foreman2@example.com", name: "Foreman"},
          actor: admin,
          tenant: to_string(org.id)
        )
        |> Ash.create()

      assert {:error, %Ash.Error.Forbidden{}} =
               foreman
               |> Ash.Changeset.for_update(:update_role, %{role: :pm},
                 actor: foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.update()
    end
  end

  describe "destroy action" do
    test "is rejected if actor tries to destroy themselves" do
      %{organization: org, user: admin} = create_org_with_admin()

      assert {:error, %Ash.Error.Forbidden{}} =
               admin
               |> Ash.Changeset.for_destroy(:destroy, %{},
                 actor: admin,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy()
    end
  end

  describe "sign_in_with_password" do
    test "JWT token contains tenant claim with organization_id" do
      %{organization: org, user: _admin} =
        create_org_with_admin(email: "jwt_test@example.com")

      assert {:ok, user} =
               User
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: "jwt_test@example.com",
                 password: "password123"
               })
               |> Ash.Query.set_context(%{private: %{ash_authentication?: true}})
               |> Ash.read_one()

      token = user.__metadata__[:token]
      assert is_binary(token)

      {:ok, claims, _resource} = AshAuthentication.Jwt.verify(token, User, tenant: to_string(org.id))
      assert claims["tenant"] == to_string(org.id)
    end
  end
end
