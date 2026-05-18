defmodule Sitevoice.Reporting.Reactors.ProcessRecordingTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :ai_pipeline

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog

  @valid_structure %{
    "labor" => [%{"crew" => "Martinez", "headcount" => 6}],
    "progress" => [%{"description" => "Poured footing"}],
    "equipment" => [],
    "materials" => [],
    "delays" => [],
    "safety" => [%{"description" => "All workers wore PPE"}],
    "accuracy_score" => 0.88
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

  describe "ProcessRecording reactor" do
    test "full pipeline: DailyLog status becomes :draft on success" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      Req.Test.stub(:whisper_req, fn conn ->
        Req.Test.json(conn, %{"text" => "Six rebar workers completed the south footing pour."})
      end)

      Req.Test.stub(:claude_req, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => Jason.encode!(@valid_structure)}]
        })
      end)

      assert {:ok, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.ProcessRecording,
                 %{log_id: log.id, organization_id: to_string(org.id)}
               )

      {:ok, updated_log} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert updated_log.status == :draft
      assert updated_log.transcript == "Six rebar workers completed the south footing pour."
      assert updated_log.accuracy_score == 0.88
    end

    test "pipeline fails when Whisper returns error: DailyLog status becomes :failed" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      Req.Test.stub(:whisper_req, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => "service unavailable"})
      end)

      assert {:error, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.ProcessRecording,
                 %{log_id: log.id, organization_id: to_string(org.id)}
               )

      {:ok, log_after} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert log_after.status == :pending
    end
  end
end
