defmodule Sitevoice.Projects.ProjectMembershipTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :projects

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Projects.ProjectMembership

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

  defp create_user(org, admin, role) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :invite,
        %{
          email: "user#{System.unique_integer()}@example.com",
          name: "#{role} User",
          role: role
        },
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    user
  end

  defp create_project(org, actor) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "proj-#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: actor,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  defp add_member(org, actor, user, project, role \\ :foreman) do
    ProjectMembership
    |> Ash.Changeset.for_create(
      :add_member,
      %{user_id: user.id, project_id: project.id, role: role},
      actor: actor,
      tenant: to_string(org.id)
    )
    |> Ash.create()
  end

  describe ":add_member action" do
    test "creates membership with organization_id from actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:ok, membership} = add_member(org, admin, foreman, project)

      assert membership.organization_id == org.id
      assert membership.user_id == foreman.id
      assert membership.project_id == project.id
    end

    test "is rejected for foreman actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      other_foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               add_member(org, foreman, other_foreman, project)
    end
  end

  describe ":update_role action" do
    test "is rejected for pm actor" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, membership} = add_member(org, admin, foreman, project)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_update(:update_role, %{role: :pm},
                 actor: pm,
                 tenant: to_string(org.id)
               )
               |> Ash.update()
    end
  end

  describe ":remove_member action" do
    test "is rejected for pm actor" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, membership} = add_member(org, admin, foreman, project)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_destroy(:remove_member, %{},
                 actor: pm,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy()
    end
  end

  describe "identity constraint" do
    test "duplicate membership for same org/project/user is rejected" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:ok, _} = add_member(org, admin, foreman, project)

      assert {:error, _} = add_member(org, admin, foreman, project)
    end
  end
end
