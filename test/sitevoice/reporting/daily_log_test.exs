defmodule Sitevoice.Reporting.DailyLogTest do
  use Sitevoice.DataCase, async: true

  @moduletag slice: :recording

  use Oban.Testing, repo: Sitevoice.Repo

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Workers.AudioProcessor

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

  defp submit_recording(org, actor, project, attrs \\ %{}) do
    defaults = %{
      date: Date.utc_today(),
      audio_key: "#{org.id}/#{project.id}/#{Date.utc_today()}/test.m4a",
      audio_duration: 90
    }

    DailyLog
    |> Ash.Changeset.for_create(
      :submit_recording,
      Map.merge(defaults, attrs) |> Map.put(:project_id, project.id),
      actor: actor,
      tenant: to_string(org.id)
    )
    |> Ash.create()
  end

  describe ":submit_recording" do
    test "sets organization_id and foreman_id from actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:ok, log} = submit_recording(org, foreman, project)

      assert log.organization_id == org.id
      assert log.foreman_id == foreman.id
    end

    test "sets status to :pending" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:ok, log} = submit_recording(org, foreman, project)

      assert log.status == :pending
    end

    test "enqueues an AudioProcessor job with correct args" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      assert {:ok, log} = submit_recording(org, foreman, project)

      assert_enqueued(
        worker: AudioProcessor,
        args: %{"log_id" => log.id, "organization_id" => to_string(org.id)}
      )
    end

    test "is rejected for an owner actor" do
      %{organization: org, user: admin} = setup_org()
      owner = create_user(org, admin, :owner)
      project = create_project(org, admin)

      assert {:error, %Ash.Error.Forbidden{}} = submit_recording(org, owner, project)
    end
  end

  describe ":apply_transcript" do
    test "updates transcript and sets status to :processing" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:ok, updated} =
               log
               |> Ash.Changeset.for_update(:apply_transcript, %{transcript: "Test transcript"},
                 authorize?: false,
                 tenant: to_string(org.id)
               )
               |> Ash.update()

      assert updated.transcript == "Test transcript"
      assert updated.status == :processing
    end
  end

  describe ":apply_structure" do
    test "updates sections and sets status to :draft" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:ok, updated} =
               log
               |> Ash.Changeset.for_update(
                 :apply_structure,
                 %{
                   labor: [%{"crew" => "Martinez", "headcount" => 6, "trade" => "Rebar"}],
                   progress: [],
                   equipment: [],
                   materials: [],
                   delays: [],
                   safety: [],
                   accuracy_score: 0.95
                 },
                 authorize?: false,
                 tenant: to_string(org.id)
               )
               |> Ash.update()

      assert updated.status == :draft
      assert length(updated.labor) == 1
    end
  end

  describe ":edit_draft" do
    test "succeeds for the foreman who submitted" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:ok, _} =
               log
               |> Ash.Changeset.for_update(:edit_draft, %{weather: "Sunny"},
                 actor: foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.update()
    end

    test "is rejected for a different foreman" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      other_foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:error, %Ash.Error.Forbidden{}} =
               log
               |> Ash.Changeset.for_update(:edit_draft, %{weather: "Sunny"},
                 actor: other_foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.update()
    end
  end

  describe ":destroy" do
    test "succeeds when status is :pending" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert :ok =
               log
               |> Ash.Changeset.for_destroy(:destroy, %{},
                 actor: foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy()
    end

    test "is rejected when status is :submitted" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      {:ok, submitted} =
        log
        |> Ash.Changeset.for_update(:approve_and_submit, %{},
          actor: foreman,
          tenant: to_string(org.id)
        )
        |> Ash.update()

      assert {:error, _} =
               submitted
               |> Ash.Changeset.for_destroy(:destroy, %{},
                 actor: foreman,
                 tenant: to_string(org.id)
               )
               |> Ash.destroy()
    end
  end

  describe ":read" do
    test "returns the log for the foreman who submitted it" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:ok, fetched} =
               Ash.get(DailyLog, log.id, actor: foreman, tenant: to_string(org.id))

      assert fetched.id == log.id
    end

    test "returns the log for a pm actor" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      pm = create_user(org, admin, :pm)
      project = create_project(org, admin)
      {:ok, log} = submit_recording(org, foreman, project)

      assert {:ok, fetched} =
               Ash.get(DailyLog, log.id, actor: pm, tenant: to_string(org.id))

      assert fetched.id == log.id
    end
  end

  describe "identity constraint" do
    test "rejects duplicate log for same org/date/foreman/project" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      date = Date.utc_today()

      {:ok, _} = submit_recording(org, foreman, project, %{date: date})

      assert {:error, _} =
               submit_recording(org, foreman, project, %{
                 date: date,
                 audio_key: "#{org.id}/#{project.id}/#{date}/duplicate.m4a"
               })
    end
  end
end
