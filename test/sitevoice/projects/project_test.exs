defmodule Sitevoice.Projects.ProjectTest do
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

  defp create_project(org, actor, attrs \\ %{}) do
    defaults = %{name: "Test Project", code: "proj-001", timezone: "America/Phoenix"}

    Project
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(defaults, attrs),
      actor: actor,
      tenant: to_string(org.id)
    )
    |> Ash.create()
  end

  describe ":create action" do
    test "sets organization_id from actor, not params" do
      %{organization: org, user: admin} = setup_org()

      assert {:ok, project} = create_project(org, admin)

      assert project.organization_id == org.id
    end

    test "normalizes code to uppercase" do
      %{organization: org, user: admin} = setup_org()

      assert {:ok, project} = create_project(org, admin, %{code: "  meridian-001 "})

      assert project.code == "MERIDIAN-001"
    end

    test "is rejected for foreman actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)

      assert {:error, %Ash.Error.Forbidden{}} = create_project(org, foreman)
    end
  end

  describe ":read action" do
    test "returns projects for org_admin" do
      %{organization: org, user: admin} = setup_org()
      {:ok, _project} = create_project(org, admin)

      assert {:ok, projects} =
               Project
               |> Ash.read(actor: admin, tenant: to_string(org.id))

      assert length(projects) >= 1
    end

    test "returns only member projects for a foreman actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      {:ok, project} = create_project(org, admin)
      {:ok, _other_project} = create_project(org, admin, %{code: "other-002"})

      # Add foreman membership to only one project
      {:ok, _membership} =
        ProjectMembership
        |> Ash.Changeset.for_create(
          :add_member,
          %{user_id: foreman.id, project_id: project.id, role: :foreman},
          actor: admin,
          tenant: to_string(org.id)
        )
        |> Ash.create()

      assert {:ok, projects} =
               Project
               |> Ash.read(actor: foreman, tenant: to_string(org.id))

      assert length(projects) == 1
      assert hd(projects).id == project.id
    end

    test "excludes projects for foreman with no membership" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      {:ok, _project} = create_project(org, admin)

      assert {:ok, projects} =
               Project
               |> Ash.read(actor: foreman, tenant: to_string(org.id))

      assert projects == []
    end
  end

  describe ":update action" do
    test "succeeds for pm actor" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      {:ok, project} = create_project(org, pm)

      assert {:ok, updated} =
               project
               |> Ash.Changeset.for_update(:update, %{name: "Updated Name"},
                 actor: pm,
                 tenant: to_string(org.id)
               )
               |> Ash.update()

      assert updated.name == "Updated Name"
    end
  end

  describe ":archive action" do
    test "sets active: false and does not delete the row for org_admin" do
      %{organization: org, user: admin} = setup_org()
      {:ok, project} = create_project(org, admin)

      assert {:ok, archived} =
               project
               |> Ash.Changeset.for_destroy(:archive, %{},
                 actor: admin,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy(return_destroyed?: true)

      assert archived.active == false

      # Row still exists in DB
      assert {:ok, still_there} =
               Ash.get(Project, project.id,
                 actor: admin,
                 tenant: to_string(org.id),
                 authorize?: false
               )

      assert still_there.id == project.id
      assert still_there.active == false
    end

    test "is rejected for pm actor" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      {:ok, project} = create_project(org, admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               project
               |> Ash.Changeset.for_destroy(:archive, %{},
                 actor: pm,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy()
    end
  end
end
