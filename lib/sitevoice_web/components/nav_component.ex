defmodule SitevoiceWeb.NavComponent do
  use Phoenix.Component
  use SitevoiceWeb, :verified_routes

  attr :current, :string, required: true
  attr :current_user, :map, required: true

  def settings_nav(assigns) do
    ~H"""
    <div style="width: 200px; flex-shrink: 0; align-self: center;">
      <div>
        <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; text-transform: uppercase; letter-spacing: 2px; margin-bottom: 16px;">
          Settings
        </div>
        <div style="display: flex; flex-direction: column; gap: 2px;">
          <.settings_nav_item href={~p"/settings/profile"} active={@current == "profile"} icon="person">
            Profile
          </.settings_nav_item>
          <%= if @current_user && @current_user.role in [:org_admin, :owner] do %>
            <.settings_nav_item href={~p"/settings/users"} active={@current == "users"} icon="users">
              Users
            </.settings_nav_item>
            <.settings_nav_item href={~p"/settings/organization"} active={@current == "org"} icon="building">
              Organization
            </.settings_nav_item>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  attr :icon, :string, default: "person"
  slot :inner_block, required: true

  defp settings_nav_item(assigns) do
    ~H"""
    <a
      href={@href}
      style={"display: flex; align-items: center; gap: 10px; padding: 9px 12px; border-radius: 6px; text-decoration: none; font-size: 13px; font-weight: 500; transition: all 0.15s ease; #{if @active, do: "background: rgba(255,92,0,0.12); color: var(--orange); border: 1px solid rgba(255,92,0,0.2);", else: "color: var(--chalk); border: 1px solid transparent;"}"}
    >
      <.settings_icon name={@icon} active={@active} />
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  defp settings_icon(%{name: "person"} = assigns) do
    ~H"""
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style={"opacity: #{if @active, do: "1", else: "0.5"}"}>
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
    </svg>
    """
  end

  defp settings_icon(%{name: "users"} = assigns) do
    ~H"""
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style={"opacity: #{if @active, do: "1", else: "0.5"}"}>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>
    </svg>
    """
  end

  defp settings_icon(%{name: "building"} = assigns) do
    ~H"""
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style={"opacity: #{if @active, do: "1", else: "0.5"}"}>
      <rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>
    </svg>
    """
  end

  attr :current_user, :map, default: nil
  attr :current_organization, :map, default: nil
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
        <li><a href={~p"/settings/profile"} class={nav_active(@current_path, "/settings")}>Settings</a></li>
        <%= if @current_user do %>
          <li class="app-nav-user-info">
            <span class="app-nav-user-name"><%= @current_user.name %> · <%= format_role(@current_user.role) %></span>
            <%= if @current_organization do %>
              <span class="app-nav-org-name"><%= @current_organization.name %></span>
            <% end %>
          </li>
        <% end %>
        <li><a href={~p"/sign-out"} class="app-nav-signout">Sign Out</a></li>
      </ul>
    </nav>
    """
  end

  defp nav_active(current, path) do
    if String.starts_with?(current, path), do: "active", else: ""
  end

  defp format_role(:foreman), do: "Foreman"
  defp format_role(:pm), do: "PM"
  defp format_role(:org_admin), do: "Admin"
  defp format_role(:owner), do: "Owner"
  defp format_role(role), do: role |> to_string() |> String.capitalize()
end
