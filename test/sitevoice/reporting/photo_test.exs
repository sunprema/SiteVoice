defmodule Sitevoice.Reporting.PhotoTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :recording

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.Photo

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
        %{name: "Test Project", code: "PROJ#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: actor,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  defp create_log(org, foreman, project) do
    {:ok, log} =
      DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{
          date: Date.utc_today(),
          audio_key: "#{org.id}/audio/test.m4a",
          audio_duration: 90,
          project_id: project.id
        },
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    log
  end

  defp upload_photo(org, actor, log, storage_key \\ nil) do
    key = storage_key || "#{org.id}/#{log.id}/photo1.jpg"

    Photo
    |> Ash.Changeset.for_create(
      :upload,
      %{storage_key: key, daily_log_id: log.id},
      actor: actor,
      tenant: to_string(org.id)
    )
    |> Ash.create()
  end

  describe ":upload" do
    test "creates photo with organization_id from actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      assert {:ok, photo} = upload_photo(org, foreman, log)

      assert photo.organization_id == org.id
    end

    test "is rejected for an owner actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      owner = create_user(org, admin, :owner)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      assert {:error, %Ash.Error.Forbidden{}} = upload_photo(org, owner, log)
    end
  end

  describe ":apply_caption" do
    test "succeeds with nil actor (system call)" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)
      {:ok, photo} = upload_photo(org, foreman, log)

      assert {:ok, updated} =
               photo
               |> Ash.Changeset.for_update(:apply_caption, %{caption: "Test caption", category: :progress},
                 authorize?: false,
                 tenant: to_string(org.id)
               )
               |> Ash.update()

      assert updated.caption == "Test caption"
      assert updated.category == :progress
    end
  end

  describe ":read" do
    test "returns photo for the log's foreman" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)
      {:ok, photo} = upload_photo(org, foreman, log)

      assert {:ok, fetched} =
               Ash.get(Photo, photo.id, actor: foreman, tenant: to_string(org.id))

      assert fetched.id == photo.id
    end
  end
end
