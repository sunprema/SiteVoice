defmodule Sitevoice.Workers.DispatchIntegrationWorkerTest do
  use Sitevoice.DataCase, async: false
  use Oban.Testing, repo: Sitevoice.Repo

  @moduletag slice: :integrations

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Integrations.Integration
  alias Sitevoice.Integrations.IntegrationEvent
  alias Sitevoice.Projects.Project
  alias Sitevoice.Projects.ProjectMembership
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Workers.DispatchIntegrationWorker

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

  defp create_project(org, admin) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "P#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: admin,
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

  defp create_integration(org, admin) do
    {:ok, integration} =
      Integration
      |> Ash.Changeset.for_create(
        :create,
        %{
          provider: :procore,
          config: %{
            "access_token" => "tok_test",
            "project_id" => "99",
            "base_url" => "https://api.procore.com"
          },
          active: true
        },
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    integration
  end

  defp add_foreman_to_project(org, admin, project, foreman) do
    {:ok, _} =
      ProjectMembership
      |> Ash.Changeset.for_create(
        :add_member,
        %{user_id: foreman.id, project_id: project.id, role: :foreman},
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()
  end

  describe "perform/1 — successful dispatch" do
    test "creates IntegrationEvent with status :sent on 201 response" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      add_foreman_to_project(org, admin, project, foreman)
      log = create_log(org, foreman, project)
      integration = create_integration(org, admin)
      org_id = to_string(org.id)

      Req.Test.stub(:procore_req, fn conn ->
        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"id" => 1001, "status" => "approved"})
      end)

      assert :ok =
               perform_job(DispatchIntegrationWorker, %{
                 "log_id" => to_string(log.id),
                 "integration_id" => to_string(integration.id),
                 "organization_id" => org_id
               })

      events = Ash.read!(IntegrationEvent, authorize?: false, tenant: org_id)
      assert length(events) == 1
      [event] = events
      assert event.status == :sent
      assert to_string(event.log_id) == to_string(log.id)
      assert to_string(event.integration_id) == to_string(integration.id)
    end
  end

  describe "perform/1 — failed dispatch" do
    test "creates IntegrationEvent with status :failed on HTTP error and returns {:error, _}" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      add_foreman_to_project(org, admin, project, foreman)
      log = create_log(org, foreman, project)
      integration = create_integration(org, admin)
      org_id = to_string(org.id)

      Req.Test.stub(:procore_req, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "internal server error"})
      end)

      assert {:error, _} =
               perform_job(DispatchIntegrationWorker, %{
                 "log_id" => to_string(log.id),
                 "integration_id" => to_string(integration.id),
                 "organization_id" => org_id
               })

      events = Ash.read!(IntegrationEvent, authorize?: false, tenant: org_id)
      assert length(events) == 1
      [event] = events
      assert event.status == :failed
    end
  end
end
