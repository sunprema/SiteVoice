defmodule Sitevoice.Accounts.Actions.RegisterOrganizationTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :auth

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.Organization

  describe "call/1" do
    test "creates org and first user in one call" do
      assert {:ok, result} =
               RegisterOrganization.call(%{
                 org_name: "Acme Corp",
                 user_email: "admin@acme.com",
                 user_password: "password123",
                 user_name: "Alice Admin"
               })

      assert result.organization.name == "Acme Corp"
      assert to_string(result.user.email) == "admin@acme.com"
      assert result.user.role == :org_admin
      assert result.user.organization_id == result.organization.id
    end

    test "returns a JWT token" do
      assert {:ok, result} =
               RegisterOrganization.call(%{
                 org_name: "BuildCo",
                 user_email: "boss@buildco.com",
                 user_password: "password123",
                 user_name: "Bob Boss"
               })

      assert is_binary(result.token)
      assert String.length(result.token) > 0
    end

    test "rolls back org creation if user creation fails" do
      org_count_before = Ash.count!(Organization, authorize?: false)

      assert {:error, _reason} =
               RegisterOrganization.call(%{
                 org_name: "Ghost Org",
                 user_email: "bad-email",
                 user_password: "short",
                 user_name: "Ghost"
               })

      org_count_after = Ash.count!(Organization, authorize?: false)
      assert org_count_before == org_count_after
    end
  end
end
