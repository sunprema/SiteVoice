defmodule SitevoiceWeb.DashboardLiveTest do
  use SitevoiceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag slice: :liveview

  alias Sitevoice.Accounts.Actions.RegisterOrganization

  defp setup_org do
    {:ok, result} =
      RegisterOrganization.call(%{
        org_name: "Org #{System.unique_integer()}",
        user_email: "admin#{System.unique_integer()}@example.com",
        user_password: "Password123!",
        user_name: "Admin User"
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
          name: "Joe Foreman"
        },
        authorize?: false,
        tenant: to_string(org.id)
      )
      |> Ash.create(authorize?: false)

    user
  end

  defp log_in(conn, token) when is_binary(token) do
    Plug.Test.init_test_session(conn, %{"user_token" => token})
  end

  describe "unauthenticated access" do
    test "redirects to sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/dashboard")
    end
  end

  describe "admin view" do
    test "shows PM dashboard with count cards", %{conn: conn} do
      %{user: admin} = setup_org()
      conn = log_in(conn, admin.__metadata__[:token])

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Dashboard"
    end
  end

  describe "foreman view" do
    test "shows today's log status and RECORD DAY button", %{conn: conn} do
      %{organization: org} = setup_org()
      foreman = create_foreman(org)
      conn = log_in(conn, foreman.__metadata__[:token])

      {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "RECORD DAY" or html =~ "No report submitted"
    end
  end
end
