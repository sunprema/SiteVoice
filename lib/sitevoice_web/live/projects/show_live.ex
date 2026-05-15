defmodule SitevoiceWeb.Projects.ShowLive do
  use SitevoiceWeb, :live_view

  require Ash.Query

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    with {:ok, project} <-
           Ash.get(Sitevoice.Projects.Project, project_id,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:memberships]
           ),
         {:ok, logs} <-
           Sitevoice.Reporting.DailyLog
           |> Ash.Query.for_read(:list_for_project, %{project_id: project_id})
           |> Ash.Query.load([:foreman])
           |> Ash.read(tenant: org_id, actor: user, authorize?: true) do
      {:ok,
       socket
       |> assign(:tenant, org_id)
       |> assign(:project, project)
       |> assign(:logs, Enum.take(logs, 30))
       |> assign(:memberships, project.memberships)
       |> assign(:show_member_form, false)
       |> assign(:member_error, nil)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("open_member_form", _params, socket) do
    {:noreply, assign(socket, :show_member_form, true)}
  end

  def handle_event("close_member_form", _params, socket) do
    {:noreply, assign(socket, show_member_form: false, member_error: nil)}
  end

  def handle_event("add_member", %{"membership" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    user_result =
      Sitevoice.Accounts.User
      |> Ash.Query.filter(email == ^params["email"])
      |> Ash.read_one(tenant: org_id, actor: user, authorize?: false)

    case user_result do
      {:ok, nil} ->
        {:noreply, assign(socket, :member_error, "User not found with that email.")}

      {:ok, target_user} ->
        membership_params = %{
          user_id: target_user.id,
          project_id: project.id,
          role: String.to_existing_atom(params["role"])
        }

        case Ash.create(Sitevoice.Projects.ProjectMembership, membership_params,
               action: :add_member,
               tenant: org_id,
               actor: user,
               authorize?: true
             ) do
          {:ok, _membership} ->
            {:ok, updated_project} =
              Ash.get(Sitevoice.Projects.Project, project.id,
                tenant: org_id,
                actor: user,
                authorize?: true,
                load: [:memberships]
              )

            {:noreply,
             socket
             |> assign(:memberships, updated_project.memberships)
             |> assign(:show_member_form, false)
             |> assign(:member_error, nil)}

          {:error, error} ->
            {:noreply, assign(socket, :member_error, format_error(error))}
        end

      {:error, _} ->
        {:noreply, assign(socket, :member_error, "Could not find user.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <body class="app-ui">
      <.nav current_user={@current_user} current_path="/projects" />
      <div class="app-page" style="padding: 40px; max-width: 1000px; margin: 0 auto;">
        <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
          <a href={~p"/projects"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
            All Projects
          </a>
          <div style="display: flex; align-items: center; gap: 16px; flex-wrap: wrap; margin-top: 12px;">
            <div class="display-heading"><%= @project.name %></div>
            <span style="font-family: var(--font-mono); font-size: 12px; color: var(--orange); background: rgba(255,92,0,0.1); border: 1px solid rgba(255,92,0,0.3); padding: 4px 12px; border-radius: 4px; letter-spacing: 2px;">
              <%= @project.code %>
            </span>
          </div>
          <div style="font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5; margin-top: 8px; text-transform: uppercase; letter-spacing: 1px;">
            <%= length(@memberships) %> members
          </div>
        </div>

        <div style="display: grid; grid-template-columns: 2fr 1fr; gap: 24px; align-items: start;">
          <%!-- Logs List --%>
          <div>
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
              <div class="section-label" style="margin-bottom: 0;">Recent Logs</div>
              <a href={~p"/projects/#{@project.id}/logs/new"} class="btn-primary" style="padding: 10px 18px; font-size: 12px;">
                + New Log
              </a>
            </div>
            <div class="card" style="padding: 0; overflow: hidden;">
              <%= if @logs == [] do %>
                <div class="empty-state" style="padding: 40px 20px;">
                  <div class="empty-state-title" style="font-size: 22px;">No Logs Yet</div>
                  <div class="empty-state-sub">Submit the first recording for this project.</div>
                </div>
              <% else %>
                <%= for log <- @logs do %>
                  <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-bottom: 1px solid rgba(61,79,101,0.3);">
                    <div>
                      <div style="font-size: 13px; color: var(--white); margin-bottom: 4px;">
                        <%= Calendar.strftime(log.date, "%b %d, %Y") %>
                      </div>
                      <div style="font-size: 11px; color: var(--chalk); opacity: 0.5; font-family: var(--font-mono);">
                        <%= log.foreman && log.foreman.name %>
                      </div>
                    </div>
                    <div style="display: flex; align-items: center; gap: 12px;">
                      <.log_status_pill status={log.status} />
                      <a href={log_link(log)} class="chevron-link">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 18 15 12 9 6"/></svg>
                      </a>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Members --%>
          <div>
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
              <div class="section-label" style="margin-bottom: 0;">Members</div>
              <%= if @current_user.role in [:pm, :org_admin, :owner] do %>
                <button class="btn-secondary" style="padding: 6px 12px; font-size: 11px;" phx-click="open_member_form">+ Add</button>
              <% end %>
            </div>

            <%= if @show_member_form do %>
              <div class="card" style="margin-bottom: 16px; border-color: var(--orange);">
                <%= if @member_error do %>
                  <div class="alert-error" style="margin-bottom: 12px; font-size: 12px;"><%= @member_error %></div>
                <% end %>
                <form phx-submit="add_member">
                  <div class="form-group">
                    <label class="form-label">Email</label>
                    <input class="form-input" type="email" name="membership[email]" required />
                  </div>
                  <div class="form-group">
                    <label class="form-label">Role</label>
                    <select class="form-select" name="membership[role]">
                      <option value="foreman">Foreman</option>
                      <option value="pm">PM</option>
                    </select>
                  </div>
                  <div style="display: flex; gap: 8px;">
                    <button type="submit" class="btn-primary" style="padding: 8px 16px; font-size: 12px;">Add</button>
                    <button type="button" class="btn-ghost" style="font-size: 12px; padding: 8px 0;" phx-click="close_member_form">Cancel</button>
                  </div>
                </form>
              </div>
            <% end %>

            <div class="card" style="padding: 0; overflow: hidden;">
              <%= if @memberships == [] do %>
                <div style="padding: 20px; color: var(--chalk); opacity: 0.5; font-size: 13px; text-align: center;">No members yet.</div>
              <% else %>
                <%= for m <- @memberships do %>
                  <div style="padding: 12px 16px; border-bottom: 1px solid rgba(61,79,101,0.3); display: flex; align-items: center; justify-content: space-between;">
                    <div style="font-size: 13px; color: var(--chalk);">
                      Member
                    </div>
                    <span style="font-family: var(--font-mono); font-size: 10px; color: var(--orange); text-transform: uppercase; letter-spacing: 1px;">
                      <%= m.role %>
                    </span>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </body>
    """
  end

  defp log_status_pill(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending -> %><span class="pill pill-pending">Pending</span>
      <% :processing -> %><span class="pill pill-active">Processing</span>
      <% :draft -> %><span class="pill pill-pending">Ready</span>
      <% :submitted -> %><span class="pill pill-done">Submitted</span>
      <% :failed -> %><span class="pill pill-failed">Failed</span>
      <% _ -> %><span class="pill pill-pending"><%= @status %></span>
    <% end %>
    """
  end

  defp log_link(log) do
    case log.status do
      s when s in [:processing, :pending] -> ~p"/logs/#{log.id}/processing"
      _ -> ~p"/logs/#{log.id}"
    end
  end

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)
end
