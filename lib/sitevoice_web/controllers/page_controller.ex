defmodule SitevoiceWeb.PageController do
  use SitevoiceWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def landing(conn, _params) do
    render(conn, :landing)
  end

  def index conn, _params do
    conn |> put_root_layout(html: {SitevoiceWeb.Layouts, :spa_root}) |> render(:index)
  end
end
