defmodule Sitevoice.Workers.WeeklyReportSchedulerWorkerTest do
  use Sitevoice.DataCase, async: false
  use Oban.Testing, repo: Sitevoice.Repo

  @moduletag slice: :weekly_report

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.WeeklyReport
  alias Sitevoice.Workers.WeeklyReportSchedulerWorker

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

  defp create_project(org, admin) do
    {:ok, project} =
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Project #{System.unique_integer()}", code: "P#{System.unique_integer()}", timezone: "America/Phoenix"},
        actor: admin,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    project
  end

  describe "perform/1" do
    test "creates WeeklyReport and enqueues WeeklyReportWorker for each org/project" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      assert :ok = perform_job(WeeklyReportSchedulerWorker, %{})

      {week_start, _} = WeeklyReportSchedulerWorker.current_week()

      {:ok, [report]} =
        Sitevoice.Reporting.get_weekly_report_by_week(project.id, week_start,
          tenant: to_string(org.id),
          authorize?: false
        )

      assert report != nil
      assert report.status == :pending

      assert_enqueued(
        worker: Sitevoice.Workers.WeeklyReportWorker,
        args: %{"report_id" => report.id, "organization_id" => to_string(org.id)}
      )
    end

    test "skips scheduling when a report for the current week already exists" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      {week_start, week_end} = WeeklyReportSchedulerWorker.current_week()

      _existing =
        WeeklyReport
        |> Ash.Changeset.for_create(:create, %{
             project_id: project.id,
             organization_id: to_string(org.id),
             week_start: week_start,
             week_end: week_end
           }, authorize?: false, tenant: to_string(org.id))
        |> Ash.create!()

      assert :ok = perform_job(WeeklyReportSchedulerWorker, %{})

      {:ok, reports} =
        Sitevoice.Reporting.list_weekly_reports_for_project(project.id,
          tenant: to_string(org.id),
          authorize?: false
        )

      assert length(reports) == 1
    end
  end
end
