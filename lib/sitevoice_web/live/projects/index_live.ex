defmodule SitevoiceWeb.Projects.IndexLive do
  use SitevoiceWeb, :live_view

  require Logger

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    projects = load_projects(org_id, user)

    socket =
      socket
      |> assign(:tenant, org_id)
      |> assign(:projects, projects)
      |> assign(:show_form, false)
      |> assign(:form_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("open_new_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, form_error: nil)}
  end

  def handle_event("save_project", %{"project" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    case Sitevoice.Projects.create_project(params,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:projects, [project | socket.assigns.projects])
         |> assign(:show_form, false)
         |> assign(:form_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :form_error, format_error(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_path="/projects" />
      <div class="app-page" style="padding: 40px; max-width: 1000px; margin: 0 auto;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
          <div>
            <div class="section-label">Your Projects</div>
            <div class="display-heading">Projects</div>
          </div>
          <%= if @current_user.role in [:pm, :org_admin, :owner] do %>
            <button class="btn-primary" phx-click="open_new_form">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              New Project
            </button>
          <% end %>
        </div>

        <%= if @show_form do %>
          <div class="card" style="margin-bottom: 24px; border-color: var(--orange);">
            <div class="section-label">New Project</div>
            <%= if @form_error do %>
              <div class="alert-error" style="margin-bottom: 16px;"><%= @form_error %></div>
            <% end %>
            <form phx-submit="save_project">
              <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px;">
                <div class="form-group">
                  <label class="form-label">Project Name</label>
                  <input class="form-input" type="text" name="project[name]" placeholder="Downtown Tower" required />
                </div>
                <div class="form-group">
                  <label class="form-label">Project Code</label>
                  <input class="form-input" type="text" name="project[code]" placeholder="DTW-001" required />
                </div>
              </div>
              <div class="form-group">
                <label class="form-label">Address (optional)</label>
                <input class="form-input" type="text" name="project[address]" placeholder="123 Main St, Phoenix AZ" />
              </div>
              <div style="display: flex; gap: 12px; margin-top: 16px;">
                <button type="submit" class="btn-primary">Create Project</button>
                <button type="button" class="btn-ghost" phx-click="close_form">Cancel</button>
              </div>
            </form>
          </div>
        <% end %>

        <%= if @projects == [] do %>
          <div class="empty-state">
            <div class="empty-state-icon">🏗</div>
            <div class="empty-state-title">No Projects Yet</div>
            <div class="empty-state-sub">Create your first project to start capturing daily logs.</div>
          </div>
        <% else %>
          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px;">
            <%= for project <- @projects do %>
              <a href={~p"/projects/#{project.id}"} style="text-decoration: none;">
                <div class="card" style="cursor: pointer;">
                  <div style="font-family: var(--font-display); font-size: 28px; letter-spacing: 1px; color: var(--white); margin-bottom: 6px;">
                    <%= project.name %>
                  </div>
                  <div style="font-family: var(--font-mono); font-size: 11px; color: var(--orange); letter-spacing: 2px; text-transform: uppercase; margin-bottom: 12px;">
                    <%= project.code %>
                  </div>
                  <div style="font-size: 12px; color: var(--chalk); opacity: 0.5; font-family: var(--font-mono);">
                    <%= project.report_count || 0 %> reports
                  </div>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp load_projects(org_id, user) do
    case Sitevoice.Projects.list_projects(
           tenant: org_id,
           actor: user,
           authorize?: true,
           load: [:report_count]
         ) do
      {:ok, projects} -> projects
      {:error, reason} ->
        Logger.error("ProjectsIndexLive failed to load projects for org=#{org_id}: #{inspect(reason)}")
        []
    end
  end

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)
end
