defmodule Sitevoice.Reporting.WeeklyReportTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :weekly_report

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Projects.Project
  alias Sitevoice.Accounts.User
  alias Sitevoice.Reporting.WeeklyReport

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
        %{email: "user#{System.unique_integer()}@example.com", name: "#{role} User", role: role},
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

  defp create_report(org, project, week_start \\ ~D[2025-05-12]) do
    week_end = Date.add(week_start, 6)

    WeeklyReport
    |> Ash.Changeset.for_create(:create, %{
         project_id: project.id,
         organization_id: to_string(org.id),
         week_start: week_start,
         week_end: week_end
       }, authorize?: false, tenant: to_string(org.id))
    |> Ash.create!()
  end

  describe ":create" do
    test "creates a report with status :pending" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      report = create_report(org, project)

      assert report.status == :pending
      assert report.week_start == ~D[2025-05-12]
      assert report.week_end == ~D[2025-05-18]
      assert report.project_id == project.id
    end

    test "prevents duplicate report for same project + week_start" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      _first = create_report(org, project, ~D[2025-05-12])

      assert_raise Ash.Error.Invalid, fn ->
        create_report(org, project, ~D[2025-05-12])
      end
    end
  end

  describe ":mark_ready" do
    test "updates all output fields and sets status :ready" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      report = create_report(org, project)

      {:ok, updated} =
        report
        |> Ash.Changeset.for_update(:mark_ready, %{
             summary: "A great week of progress.",
             key_accomplishments: ["Poured foundation", "Erected steel frame"],
             outstanding_issues: ["Crane unavailable Friday"],
             trends: [%{"description" => "Weather delays", "severity" => "low"}],
             pdf_key: "org/weekly-reports/#{report.id}.pdf",
             total_labor_hours: 200.0,
             total_headcount_days: 25,
             daily_log_count: 4,
             generated_at: DateTime.utc_now()
           }, authorize?: false, tenant: to_string(org.id))
        |> Ash.update()

      assert updated.status == :ready
      assert updated.summary == "A great week of progress."
      assert length(updated.key_accomplishments) == 2
      assert length(updated.outstanding_issues) == 1
      assert updated.total_labor_hours == 200.0
      assert updated.daily_log_count == 4
    end
  end

  describe ":mark_failed" do
    test "sets status to :failed" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      report = create_report(org, project)

      {:ok, failed} =
        report
        |> Ash.Changeset.for_update(:mark_failed, %{}, authorize?: false, tenant: to_string(org.id))
        |> Ash.update()

      assert failed.status == :failed
    end
  end

  describe ":list_for_project" do
    test "pm can list reports for their project" do
      %{organization: org, user: admin} = setup_org()
      pm = create_user(org, admin, :pm)
      project = create_project(org, admin)

      _report = create_report(org, project)

      {:ok, reports} =
        Sitevoice.Reporting.list_weekly_reports_for_project(project.id,
          tenant: to_string(org.id),
          actor: pm,
          authorize?: true
        )

      assert length(reports) == 1
    end

    test "foreman sees empty list (policy filters forbidden records)" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      _report = create_report(org, project)

      assert {:ok, []} =
               Sitevoice.Reporting.list_weekly_reports_for_project(project.id,
                 tenant: to_string(org.id),
                 actor: foreman,
                 authorize?: true
               )
    end
  end

  describe ":get_by_week" do
    test "returns the report for a given project and week_start" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)
      week_start = ~D[2025-05-12]

      _report = create_report(org, project, week_start)

      {:ok, [found]} =
        Sitevoice.Reporting.get_weekly_report_by_week(project.id, week_start,
          tenant: to_string(org.id),
          authorize?: false
        )

      assert found.week_start == week_start
    end

    test "returns empty list when no report exists for the week" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      {:ok, result} =
        Sitevoice.Reporting.get_weekly_report_by_week(project.id, ~D[2025-01-06],
          tenant: to_string(org.id),
          authorize?: false
        )

      assert result == []
    end
  end
end
