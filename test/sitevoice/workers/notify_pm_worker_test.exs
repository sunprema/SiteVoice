defmodule Sitevoice.Workers.NotifyPmWorkerTest do
  use Sitevoice.DataCase, async: false
  use Oban.Testing, repo: Sitevoice.Repo

  import Swoosh.TestAssertions

  @moduletag slice: :notifications

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Projects.ProjectMembership
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Workers.NotifyPmWorker

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

  defp set_pdf_key(log, org, pdf_key) do
    {:ok, updated} =
      log
      |> Ash.Changeset.for_update(:update_pdf, %{pdf_key: pdf_key},
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.update()

    updated
  end

  defp add_membership(org, admin, project, user, role) do
    {:ok, membership} =
      ProjectMembership
      |> Ash.Changeset.for_create(
        :add_member,
        %{user_id: user.id, project_id: project.id, role: role},
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    membership
  end

  defp drain_mailbox do
    receive do
      {:email, _} -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  describe "perform/1" do
    test "sends email to PM when log has a pdf_key" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      pm = create_user(org, admin, :pm)
      project = create_project(org, admin)
      add_membership(org, admin, project, foreman, :foreman)
      add_membership(org, admin, project, pm, :pm)
      log = create_log(org, foreman, project)
      pdf_key = "#{org.id}/#{project.id}/2025/5/#{log.id}.pdf"
      log = set_pdf_key(log, org, pdf_key)

      drain_mailbox()

      assert :ok =
               perform_job(NotifyPmWorker, %{
                 "log_id" => log.id,
                 "organization_id" => to_string(org.id)
               })

      assert_email_sent(fn email ->
        assert email.subject =~ "Daily Log"
        assert email.to == [{"pm User", to_string(pm.email)}]
      end)
    end

    test "returns error when log has no pdf_key" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)

      assert {:error, :no_pdf} =
               perform_job(NotifyPmWorker, %{
                 "log_id" => log.id,
                 "organization_id" => to_string(org.id)
               })
    end

    test "sends no email when project has no PM members" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)
      log = create_log(org, foreman, project)
      pdf_key = "#{org.id}/#{project.id}/2025/5/#{log.id}.pdf"
      log = set_pdf_key(log, org, pdf_key)

      drain_mailbox()

      assert :ok =
               perform_job(NotifyPmWorker, %{
                 "log_id" => log.id,
                 "organization_id" => to_string(org.id)
               })

      refute_email_sent()
    end
  end
end
