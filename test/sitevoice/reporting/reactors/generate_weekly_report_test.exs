defmodule Sitevoice.Reporting.Reactors.GenerateWeeklyReportTest do
  use Sitevoice.DataCase, async: false

  @moduletag slice: :weekly_report

  alias Sitevoice.Accounts.Actions.RegisterOrganization
  alias Sitevoice.Accounts.User
  alias Sitevoice.Projects.Project
  alias Sitevoice.Reporting.DailyLog
  alias Sitevoice.Reporting.WeeklyReport

  @valid_summary %{
    "summary" => "A productive week. Foundation work advanced on schedule.",
    "key_accomplishments" => ["Foundation poured", "Steel erected"],
    "outstanding_issues" => ["Crane unavailable Friday"],
    "trends" => [%{"description" => "Weather delays", "severity" => "low"}]
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

  defp create_submitted_log(org, foreman, project, date) do
    org_id = to_string(org.id)

    log =
      DailyLog
      |> Ash.Changeset.for_create(
        :start_log,
        %{date: date, project_id: project.id},
        actor: foreman,
        tenant: org_id
      )
      |> Ash.create!()

    log =
      log
      |> Ash.Changeset.for_update(:apply_transcript, %{transcript: "Concrete crew poured south footing."},
           authorize?: false, tenant: org_id)
      |> Ash.update!()

    log =
      log
      |> Ash.Changeset.for_update(:apply_structure, %{
           labor: [%{"trade" => "Concrete", "crew" => "Team A", "headcount" => 5, "hours" => 8.0}],
           progress: [%{"description" => "Foundation poured", "location" => "Building A", "percentage_complete" => 75}],
           equipment: [], materials: [], delays: [], safety: [], accuracy_score: 0.9
         }, authorize?: false, tenant: org_id)
      |> Ash.update!()

    log
    |> Ash.Changeset.for_update(:approve_and_submit, %{}, actor: foreman, tenant: org_id)
    |> Ash.update!()
  end

  defp create_weekly_report(org, project, week_start) do
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

  describe "GenerateWeeklyReport reactor" do
    test "WeeklyReport status becomes :ready on success" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      week_start = ~D[2025-05-12]

      _log1 = create_submitted_log(org, foreman, project, ~D[2025-05-12])
      _log2 = create_submitted_log(org, foreman, project, ~D[2025-05-13])
      _log3 = create_submitted_log(org, foreman, project, ~D[2025-05-14])

      report = create_weekly_report(org, project, week_start)

      Req.Test.stub(:claude_req, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => Jason.encode!(@valid_summary)}]
        })
      end)

      assert {:ok, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.GenerateWeeklyReport,
                 %{report_id: report.id, organization_id: to_string(org.id)}
               )

      {:ok, updated} =
        Ash.get(WeeklyReport, report.id,
          authorize?: false,
          tenant: to_string(org.id)
        )

      assert updated.status == :ready
      assert updated.pdf_key =~ "weekly-reports"
      assert updated.summary == @valid_summary["summary"]
      assert updated.daily_log_count == 3
      assert updated.total_labor_hours > 0
    end

    test "WeeklyReport status stays :generating and compensates on Claude failure" do
      %{organization: org, user: admin} = setup_org()
      foreman = create_user(org, admin, :foreman)
      project = create_project(org, admin)

      week_start = ~D[2025-05-12]
      _log = create_submitted_log(org, foreman, project, ~D[2025-05-12])
      report = create_weekly_report(org, project, week_start)

      report
      |> Ash.Changeset.for_update(:mark_generating, %{}, authorize?: false, tenant: to_string(org.id))
      |> Ash.update!()

      Req.Test.stub(:claude_req, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"error" => "internal server error"})
      end)

      assert {:error, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.GenerateWeeklyReport,
                 %{report_id: report.id, organization_id: to_string(org.id)}
               )

      {:ok, failed} =
        Ash.get(WeeklyReport, report.id,
          authorize?: false,
          tenant: to_string(org.id)
        )

      assert failed.status == :failed
    end

    test "report with zero submitted logs still generates successfully" do
      %{organization: org, user: admin} = setup_org()
      project = create_project(org, admin)

      week_start = ~D[2025-05-12]
      report = create_weekly_report(org, project, week_start)

      Req.Test.stub(:claude_req, fn conn ->
        empty_summary = %{
          "summary" => "No activity logged this week.",
          "key_accomplishments" => [],
          "outstanding_issues" => [],
          "trends" => []
        }
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => Jason.encode!(empty_summary)}]
        })
      end)

      assert {:ok, _} =
               Reactor.run(
                 Sitevoice.Reporting.Reactors.GenerateWeeklyReport,
                 %{report_id: report.id, organization_id: to_string(org.id)}
               )

      {:ok, updated} = Ash.get(WeeklyReport, report.id, authorize?: false, tenant: to_string(org.id))
      assert updated.status == :ready
      assert updated.daily_log_count == 0
    end
  end
end
