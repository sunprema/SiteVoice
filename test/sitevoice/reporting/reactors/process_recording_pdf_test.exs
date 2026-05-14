defmodule Sitevoice.Reporting.Reactors.ProcessRecordingPdfTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :pdf_generation

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog

  @valid_structure %{
    "labor" => [%{"crew" => "Martinez", "headcount" => 6, "trade" => "Carpenter", "hours" => 8}],
    "progress" => [%{"description" => "Poured south footing"}],
    "equipment" => [],
    "materials" => [],
    "delays" => [],
    "safety" => [],
    "accuracy_score" => 0.91
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

  defp stub_external_calls do
    Req.Test.stub(:whisper_req, fn conn ->
      Req.Test.json(conn, %{"text" => "Six rebar workers completed the south footing pour."})
    end)

    Req.Test.stub(:claude_req, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => Jason.encode!(@valid_structure)}]
      })
    end)
  end

  describe "ProcessRecording with PDF generation" do
    test "pipeline populates pdf_key on DailyLog after successful run" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      stub_external_calls()

      assert {:ok, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.ProcessRecording,
                 %{log_id: log.id, organization_id: to_string(org.id)}
               )

      {:ok, updated_log} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert updated_log.status == :draft
      assert is_binary(updated_log.pdf_key)
      assert String.contains?(updated_log.pdf_key, to_string(org.id))
      assert String.ends_with?(updated_log.pdf_key, ".pdf")
    end

    test "pipeline sets status :draft and does not overwrite structured data" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      stub_external_calls()

      assert {:ok, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.ProcessRecording,
                 %{log_id: log.id, organization_id: to_string(org.id)}
               )

      {:ok, updated_log} = Ash.get(DailyLog, log.id, authorize?: false, tenant: to_string(org.id))
      assert updated_log.status == :draft
      assert updated_log.accuracy_score == 0.91
      assert length(updated_log.labor) == 1
    end

    test "pipeline fails when Imprintor returns error" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      stub_external_calls()
      Application.put_env(:sitevoice, :imprintor_stub_result, {:error, "crash"})

      on_exit(fn -> Application.delete_env(:sitevoice, :imprintor_stub_result) end)

      assert {:error, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.ProcessRecording,
                 %{log_id: log.id, organization_id: to_string(org.id)}
               )
    end
  end
end
