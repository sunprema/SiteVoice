defmodule Sitevoice.Integrations.IntegrationTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :integrations

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Integrations.Integration

  defp setup_org do
    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "admin#{System.unique_integer()}@example.com",
        user_password: "password123",
        user_name: "Admin User"
      })

    result
  end

  describe "create/read" do
    test "org_admin can create and read an integration" do
      %{organization: org, user: admin} = setup_org()
      org_id = to_string(org.id)

      {:ok, integration} =
        Integration
        |> Ash.Changeset.for_create(
          :create,
          %{
            provider: :procore,
            config: %{"access_token" => "tok_123", "project_id" => "42"},
            active: true
          },
          actor: admin,
          tenant: org_id
        )
        |> Ash.create()

      assert integration.provider == :procore
      assert integration.active == true

      integrations = Ash.read!(Integration, actor: admin, tenant: org_id)
      assert Enum.any?(integrations, &(&1.id == integration.id))
    end

    test "organization_id is set from actor, not from params" do
      %{organization: org, user: admin} = setup_org()
      org_id = to_string(org.id)

      {:ok, integration} =
        Integration
        |> Ash.Changeset.for_create(
          :create,
          %{
            provider: :procore,
            config: %{"access_token" => "tok_abc"},
            active: true
          },
          actor: admin,
          tenant: org_id
        )
        |> Ash.create()

      assert to_string(integration.organization_id) == org_id
    end

    test "integration can be deactivated via update" do
      %{organization: org, user: admin} = setup_org()
      org_id = to_string(org.id)

      {:ok, integration} =
        Integration
        |> Ash.Changeset.for_create(
          :create,
          %{
            provider: :procore,
            config: %{"access_token" => "tok_123"},
            active: true
          },
          actor: admin,
          tenant: org_id
        )
        |> Ash.create()

      {:ok, updated} =
        integration
        |> Ash.Changeset.for_update(:update, %{active: false},
          actor: admin,
          tenant: org_id
        )
        |> Ash.update()

      assert updated.active == false
    end
  end
end
