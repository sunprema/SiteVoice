defmodule SitevoiceWeb.NavComponent do
  use Phoenix.Component
  use SitevoiceWeb, :verified_routes

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: "/"

  def nav(assigns) do
    ~H"""
    <nav class="app-nav">
      <a href={~p"/dashboard"} class="app-nav-logo">
        Site<span class="accent">Voice</span>&nbsp;AI
        <span class="logo-badge">Beta</span>
      </a>
      <ul class="app-nav-links">
        <li><a href={~p"/dashboard"} class={nav_active(@current_path, "/dashboard")}>Dashboard</a></li>
        <li><a href={~p"/projects"} class={nav_active(@current_path, "/projects")}>Projects</a></li>
        <%= if @current_user && @current_user.role in [:pm, :org_admin, :owner] do %>
          <li><a href={~p"/logs"} class={nav_active(@current_path, "/logs")}>Logs</a></li>
        <% end %>
        <li><a href={~p"/sign-out"} class="app-nav-signout">Sign Out</a></li>
      </ul>
    </nav>
    """
  end

  defp nav_active(current, path) do
    if String.starts_with?(current, path), do: "active", else: ""
  end
end
