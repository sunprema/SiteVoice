defmodule SitevoiceWeb.Plugs.SetTenantTest do
  use SitevoiceWeb.ConnCase, async: true

  @moduletag slice: :auth

  alias SitevoiceWeb.Plugs.SetTenant

  describe "call/2" do
    test "sets Ash tenant when current_user is present" do
      org_id = Ash.UUID.generate()

      user = %Sitevoice.Accounts.User{organization_id: org_id}

      conn =
        build_conn()
        |> assign(:current_user, user)
        |> SetTenant.call([])

      assert Ash.PlugHelpers.get_tenant(conn) == to_string(org_id)
    end

    test "no-op when current_user is nil" do
      conn =
        build_conn()
        |> assign(:current_user, nil)
        |> SetTenant.call([])

      assert Ash.PlugHelpers.get_tenant(conn) == nil
    end

    test "no-op when current_user is not assigned" do
      conn =
        build_conn()
        |> SetTenant.call([])

      assert Ash.PlugHelpers.get_tenant(conn) == nil
    end
  end
end
