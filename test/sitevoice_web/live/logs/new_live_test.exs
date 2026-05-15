defmodule SitevoiceWeb.Logs.NewLiveTest do
  use SitevoiceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag slice: :liveview

  alias Sitevoice.Accounts.Actions.RegisterOrganization

  defp setup_org_and_project do
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

    %{organization: org, user: admin, project: project}
  end

  defp log_in(conn, token), do: Plug.Test.init_test_session(conn, %{"user_token" => token})

  test "form renders with upload inputs", %{conn: conn} do
    %{user: admin, project: project} = setup_org_and_project()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/logs/new")
    assert html =~ "Audio Recording"
    assert html =~ "Submit Recording"
  end

  test "submit button is disabled with no audio", %{conn: conn} do
    %{user: admin, project: project} = setup_org_and_project()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/logs/new")
    assert html =~ "disabled" or html =~ "opacity: 0.4"
  end
end
