defmodule SitevoiceWeb.Projects.IndexLiveTest do
  use SitevoiceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag slice: :liveview

  alias Sitevoice.Accounts.Actions.RegisterOrganization

  defp setup_org do
    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "pm#{System.unique_integer()}@example.com",
        user_password: "Password123!",
        user_name: "PM User"
      })

    result
  end

  defp create_foreman(org) do
    {:ok, user} =
      Sitevoice.Accounts.User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{
          email: "foreman#{System.unique_integer()}@example.com",
          password: "Password123!",
          password_confirmation: "Password123!",
          organization_id: org.id,
          role: :foreman,
          name: "Foreman User"
        },
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.create(authorize?: false)

    user
  end

  defp log_in(conn, token), do: Plug.Test.init_test_session(conn, %{"user_token" => token})

  test "project list renders for authenticated user", %{conn: conn} do
    %{user: admin} = setup_org()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/projects")
    assert html =~ "Projects"
  end

  test "New Project button is visible to pm/admin", %{conn: conn} do
    %{user: admin} = setup_org()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/projects")
    assert html =~ "New Project"
  end

  test "foreman cannot see New Project button", %{conn: conn} do
    %{organization: org} = setup_org()
    foreman = create_foreman(org)
    conn = log_in(conn, foreman.__metadata__[:token])

    {:ok, _view, html} = live(conn, ~p"/projects")
    refute html =~ "New Project"
  end

  test "New Project form creates project and updates list", %{conn: conn} do
    %{user: admin} = setup_org()
    conn = log_in(conn, admin.__metadata__[:token])

    {:ok, view, _html} = live(conn, ~p"/projects")
    view |> element("button", "New Project") |> render_click()

    code = "TST-#{System.unique_integer()}"

    html =
      view
      |> form("form[phx-submit='save_project']", project: %{name: "Test Project", code: code})
      |> render_submit()

    assert html =~ "Test Project" or html =~ code
  end
end
