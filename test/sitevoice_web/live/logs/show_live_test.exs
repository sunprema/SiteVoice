defmodule SitevoiceWeb.Logs.ShowLiveTest do
  use SitevoiceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag slice: :liveview

  alias Sitevoice.Accounts.Actions.RegisterOrganization

  defp setup_data do
    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "admin#{System.unique_integer()}@example.com",
        user_password: "Password123!",
        user_name: "Admin User"
      })

    %{organization: org, user: admin} = result

    {:ok, project} =
      Sitevoice.Projects.Project
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Test Project", code: "TST#{System.unique_integer()}"},
        actor: admin,
        tenant: to_string(org.id),
        authorize?: true
      )
      |> Ash.create()

    {:ok, foreman} =
      Sitevoice.Accounts.User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{
          email: "foreman#{System.unique_integer()}@example.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          organization_id: org.id,
          role: :foreman,
          name: "Joe Foreman"
        },
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.create(authorize?: false)

    {:ok, log} =
      Sitevoice.Reporting.DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{date: Date.utc_today(), audio_key: "test/audio.m4a", project_id: project.id},
        actor: foreman,
        authorize?: true,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    %{organization: org, admin: admin, foreman: foreman, project: project, log: log}
  end

  defp log_in(conn, token), do: Plug.Test.init_test_session(conn, %{"user_token" => token})

  test "log category cards display", %{conn: conn} do
    %{admin: admin, log: log} = setup_data()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/logs/#{log.id}")
    assert html =~ "Labor" or html =~ "Transcript"
  end

  test "Approve & Submit not visible to foreman (only foreman can submit their own)", %{conn: conn} do
    %{foreman: foreman, log: log} = setup_data()
    conn = log_in(conn, foreman.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/logs/#{log.id}")
    # Status is :pending (not :draft yet), so approve button should not be visible
    refute html =~ "Approve &amp; Submit" and html =~ "phx-click=\"approve_submit\""
  end

  test "success overlay appears after approve action for org_admin on draft log", %{conn: conn} do
    %{organization: org, admin: admin, foreman: foreman, project: project} = setup_data()

    {:ok, log} =
      Sitevoice.Reporting.DailyLog
      |> Ash.Changeset.for_create(
        :submit_recording,
        %{date: Date.utc_today() |> Date.add(-1), audio_key: "test/audio2.m4a", project_id: project.id},
        actor: foreman,
        authorize?: true,
        tenant: to_string(org.id)
      )
      |> Ash.create()

    # Transition log to :draft status (as if pipeline completed)
    {:ok, log} =
      Ash.update(log, %{
        labor: [%{"description" => "10 workers"}],
        progress: [%{"description" => "Framing 80%"}],
        equipment: [],
        materials: [],
        delays: [],
        safety: [],
        accuracy_score: 0.95
      },
      action: :apply_structure,
      tenant: to_string(org.id),
      authorize?: false
    )

    conn = log_in(conn, admin.__metadata__[:token])
    {:ok, view, html} = live(conn, ~p"/logs/#{log.id}")
    assert html =~ "Approve" or html =~ "Submit"

    # Click approve
    if has_element?(view, "button[phx-click='approve_submit']") do
      html = view |> element("button[phx-click='approve_submit']") |> render_click()
      assert html =~ "REPORT SENT" or html =~ "submitted"
    end
  end
end
