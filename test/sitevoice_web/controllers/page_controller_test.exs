defmodule SitevoiceWeb.PageControllerTest do
  use SitevoiceWeb.ConnCase

  @moduletag slice: :liveview

  test "GET / returns 200 with landing content", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "SPEAK"
    assert html_response(conn, 200) =~ "BUILD YOUR REPORT"
  end

  test "GET / links to /register for CTAs", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ ~p"/register"
  end
end
