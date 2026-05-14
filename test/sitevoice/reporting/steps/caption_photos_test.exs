defmodule Sitevoice.Steps.CaptionPhotosTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :ai_pipeline

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.{DailyLog, Photo}
  alias Sitevoice.Steps.CaptionPhotos

  setup do
    Req.Test.stub(:claude_req, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => "Crane lifting concrete rebar section"}]
      })
    end)

    :ok
  end

  defp setup_fixtures do
    {:ok, %{organization: org, user: admin}} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "admin#{System.unique_integer()}@example.com",
        user_password: "password123",
        user_name: "Admin User"
      })

    {:ok, foreman} =
      User
      |> Ash.Changeset.for_create(
        :invite,
        %{
          email: "foreman#{System.unique_integer()}@example.com",
          name: "Foreman",
          role: :foreman
        },
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "P#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    {:ok, log} =
      DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{
          date: Date.utc_today(),
          audio_key: "#{org.id}/#{project.id}/#{Date.utc_today()}/test.m4a",
          audio_duration: 90,
          project_id: project.id
        },
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    {:ok, photo} =
      Photo
      |> Ash.Changeset.for_create(
        :upload,
        %{
          storage_key: "#{org.id}/#{project.id}/#{log.id}/photo123.jpg",
          taken_at: DateTime.utc_now(),
          daily_log_id: log.id
        },
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    %{org: org, log: log, photo: photo}
  end

  describe "run/3 happy path" do
    test "updates photo with caption and inferred category" do
      %{org: org, photo: photo} = setup_fixtures()

      assert {:ok, updated_photos} =
               CaptionPhotos.run(
                 %{
                   photo_keys: [photo],
                   transcript: "Crane lifted the concrete rebar section to the third floor",
                   organization_id: to_string(org.id)
                 },
                 %{},
                 []
               )

      assert length(updated_photos) == 1
      [updated] = updated_photos
      assert updated.caption == "Crane lifting concrete rebar section"
      assert updated.category == :equipment
    end

    test "returns ok with empty list when no photos" do
      %{org: org} = setup_fixtures()

      assert {:ok, []} =
               CaptionPhotos.run(
                 %{
                   photo_keys: [],
                   transcript: "No photos today",
                   organization_id: to_string(org.id)
                 },
                 %{},
                 []
               )
    end
  end

  describe "compensate/4" do
    test "returns :ok" do
      assert :ok = CaptionPhotos.compensate(:reason, %{}, %{}, [])
    end
  end
end
