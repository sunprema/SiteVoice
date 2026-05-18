defmodule Sitevoice.Projects.ProjectBriefTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :clarification

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project

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
          name: "#{role}",
          role: role
        },
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    user
  end

  defp create_project(org, actor, attrs \\ %{}) do
    Project
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{name: "P #{System.unique_integer()}", code: "C#{System.unique_integer()}"},
        attrs
      ),
      actor: actor,
      tenant: to_string(org.id)
    )
    |> Ash.create()
  end

  describe "defaults" do
    test "project gets sensible brief defaults on create" do
      %{organization: org, user: admin} = setup_org()

      {:ok, project} = create_project(org, admin)

      assert project.required_sections == [:labor, :progress, :safety]
      assert is_binary(project.daily_log_context)
      assert String.length(project.daily_log_context) > 0
      assert project.daily_log_min_accuracy == 0.7
    end

    test "create accepts custom brief values" do
      %{organization: org, user: admin} = setup_org()

      attrs = %{
        required_sections: [:labor, :safety],
        daily_log_context: "Hospital build — call out infection control.",
        daily_log_min_accuracy: 0.8
      }

      {:ok, project} = create_project(org, admin, attrs)

      assert project.required_sections == [:labor, :safety]
      assert project.daily_log_context =~ "infection control"
      assert project.daily_log_min_accuracy == 0.8
    end
  end

  describe ":update_daily_log_brief" do
    test "pm can update" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      {:ok, project} = create_project(org, admin)

      {:ok, updated} =
        project
        |> Ash.Changeset.for_update(
          :update_daily_log_brief,
          %{required_sections: [:labor], daily_log_min_accuracy: 0.9},
          actor: pm,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert updated.required_sections == [:labor]
      assert updated.daily_log_min_accuracy == 0.9
    end

    test "foreman cannot update brief" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      {:ok, project} = create_project(org, admin)

      result =
        project
        |> Ash.Changeset.for_update(
          :update_daily_log_brief,
          %{required_sections: [:labor]},
          actor: foreman,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end
end
