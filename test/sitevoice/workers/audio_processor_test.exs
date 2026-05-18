defmodule Sitevoice.Workers.AudioProcessorTest do
  use Sitevoice.DataCase, async: false
  use Oban.Testing, repo: Sitevoice.Repo

  @moduletag slice: :ai_pipeline

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Workers.AudioProcessor

  @valid_structure %{
    "labor" => [%{"crew" => "A", "headcount" => 4, "trade" => "Carpenter", "hours" => 8}],
    "progress" => [%{"description" => "Poured footing on south wall"}],
    "equipment" => [],
    "materials" => [],
    "delays" => [],
    "safety" => [%{"description" => "All workers wore PPE"}],
    "accuracy_score" => 0.85
  }

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

  defp create_foreman(org, admin) do
    {:ok, user} =
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

    user
  end

  defp create_project(org, actor) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "P#{System.unique_integer()}", timezone: "America/Phoenix"},
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
          audio_key: "#{org.id}/#{project.id}/#{Date.utc_today()}/test.m4a",
          audio_duration: 90,
          project_id: project.id
        },
        actor: foreman,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    log
  end

  describe "perform/1" do
    test "returns :ok and sets DailyLog status to :draft on success" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      Req.Test.stub(:whisper_req, fn conn ->
        Req.Test.json(conn, %{"text" => "Poured footing on south wall."})
      end)

      Req.Test.stub(:claude_req, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => Jason.encode!(@valid_structure)}]
        })
      end)

      job = %Oban.Job{args: %{"log_id" => log.id, "organization_id" => to_string(org.id)}}
      assert :ok = AudioProcessor.perform(job)

      {:ok, updated} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert updated.status == :draft
    end

    test "returns error and sets DailyLog status to :failed when pipeline fails" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      Req.Test.stub(:whisper_req, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "server error"})
      end)

      job = %Oban.Job{args: %{"log_id" => log.id, "organization_id" => to_string(org.id)}}
      assert {:error, _} = AudioProcessor.perform(job)

      {:ok, updated} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert updated.status == :failed
    end
  end
end
