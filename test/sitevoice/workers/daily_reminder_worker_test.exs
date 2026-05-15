defmodule Sitevoice.Workers.DailyReminderWorkerTest do
  use Sitevoice.DataCase, async: false
  use Oban.Testing, repo: Sitevoice.Repo

  import Swoosh.TestAssertions

  @moduletag slice: :notifications

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Workers.DailyReminderWorker

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
          name: "Foreman User",
          role: :foreman
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

  defp create_submitted_log(org, foreman, project) do
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

    {:ok, submitted} =
      log
      |> Ash.Changeset.for_update(:approve_and_submit, %{},
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.update()

    submitted
  end

  defp drain_mailbox do
    receive do
      {:email, _} -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  describe "perform/1" do
    test "sends reminder to foreman with no submitted log today" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)

      drain_mailbox()

      assert :ok = perform_job(DailyReminderWorker, %{})

      assert_email_sent(fn email ->
        assert email.subject =~ "Reminder"
        assert email.to == [{"Foreman User", to_string(foreman.email)}]
      end)
    end

    test "does not send reminder to foreman who has already submitted today" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_foreman(org, admin)
      project = create_project(org, admin)
      _log = create_submitted_log(org, foreman, project)

      drain_mailbox()

      assert :ok = perform_job(DailyReminderWorker, %{})

      refute_email_sent()
    end
  end
end
