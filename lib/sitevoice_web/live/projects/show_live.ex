defmodule SitevoiceWeb.Projects.ShowLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  require Logger

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    with {:ok, project} <-
           Sitevoice.Projects.get_project(project_id,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:memberships]
           ),
         {:ok, logs} <-
           Sitevoice.Reporting.list_logs_for_project(project_id,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:foreman]
           ),
         {:ok, memberships} <-
           Sitevoice.Projects.list_project_memberships(project_id,
             tenant: org_id,
             actor: user,
             authorize?: true
           ) do
      addable_users =
        if user.role in [:pm, :org_admin, :owner] do
          case Sitevoice.Accounts.list_users(tenant: org_id, actor: user, authorize?: true) do
            {:ok, org_users} ->
              member_ids = MapSet.new(memberships, & &1.user_id)
              Enum.filter(org_users, &(not MapSet.member?(member_ids, &1.id) and &1.active))

            _ ->
              []
          end
        else
          []
        end

      crew_templates = load_crew_templates(project_id, org_id, user)

      {:ok,
       socket
       |> assign(:tenant, org_id)
       |> assign(:project, project)
       |> assign(:logs, Enum.take(logs, 30))
       |> assign(:memberships, memberships)
       |> assign(:addable_users, addable_users)
       |> assign(:show_member_form, false)
       |> assign(:member_error, nil)
       |> assign(:confirm_remove, nil)
       |> assign(:crew_templates, crew_templates)
       |> assign(:show_crew_form, false)
       |> assign(:crew_error, nil)}
    else
      error ->
        Logger.error("Projects.ShowLive mount failed for user=#{socket.assigns.current_user.id} project_id=#{project_id}: #{inspect(error)}")

        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("open_member_form", _params, socket) do
    {:noreply, assign(socket, show_member_form: true, member_error: nil)}
  end

  def handle_event("close_member_form", _params, socket) do
    {:noreply, assign(socket, show_member_form: false, member_error: nil)}
  end

  def handle_event("add_member", %{"membership" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    membership_params = %{
      user_id: params["user_id"],
      project_id: project.id,
      role: String.to_existing_atom(params["role"])
    }

    case Sitevoice.Projects.add_member(membership_params,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> reload_memberships()
         |> assign(:show_member_form, false)
         |> assign(:member_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :member_error, format_error(error))}
    end
  end

  def handle_event("change_membership_role", %{"id" => id, "role" => role}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    membership = Enum.find(socket.assigns.memberships, &(to_string(&1.id) == id))

    case Sitevoice.Projects.update_membership_role(membership, %{role: String.to_existing_atom(role)},
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _} ->
        {:noreply, reload_memberships(socket)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, format_error(error))}
    end
  end

  def handle_event("confirm_remove_member", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_remove, id)}
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :confirm_remove, nil)}
  end

  def handle_event("remove_member", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    id = socket.assigns.confirm_remove

    membership = Enum.find(socket.assigns.memberships, &(to_string(&1.id) == id))

    case Sitevoice.Projects.remove_membership(membership,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      :ok ->
        {:noreply,
         socket
         |> reload_memberships()
         |> assign(:confirm_remove, nil)
         |> put_flash(:info, "Member removed.")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:confirm_remove, nil)
         |> put_flash(:error, format_error(error))}
    end
  end

  def handle_event("open_crew_form", _params, socket) do
    {:noreply, assign(socket, show_crew_form: true, crew_error: nil)}
  end

  def handle_event("close_crew_form", _params, socket) do
    {:noreply, assign(socket, show_crew_form: false, crew_error: nil)}
  end

  def handle_event("add_crew", %{"crew" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    headcount =
      case Integer.parse(params["headcount"] || "1") do
        {n, _} -> max(1, n)
        :error -> 1
      end

    trade =
      case params["trade"] do
        t when t in ~w(concrete framing electrical plumbing steel hvac general) ->
          String.to_existing_atom(t)
        _ ->
          :general
      end

    crew_params = %{
      name: params["name"],
      trade: trade,
      subcontractor: presence(params["subcontractor"]),
      default_headcount: headcount,
      project_id: project.id
    }

    case Sitevoice.Reporting.create_crew_template(crew_params,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _template} ->
        templates = load_crew_templates(project.id, org_id, user)
        {:noreply, socket |> assign(:crew_templates, templates) |> assign(:show_crew_form, false) |> assign(:crew_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :crew_error, format_error(error))}
    end
  end

  def handle_event("deactivate_crew", %{"id" => template_id}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    case Ash.get(Sitevoice.Reporting.CrewTemplate, template_id,
           authorize?: false,
           tenant: org_id
         ) do
      {:ok, tmpl} ->
        Ash.update!(tmpl, %{active: false},
          action: :update,
          authorize?: false,
          tenant: org_id
        )

        templates = load_crew_templates(project.id, org_id, user)
        {:noreply, assign(socket, :crew_templates, templates)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp load_crew_templates(project_id, org_id, user) do
    case Sitevoice.Reporting.list_crew_templates(project_id,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, templates} -> templates
      _ -> []
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: String.trim(s) |> then(&if &1 == "", do: nil, else: &1)

  defp reload_memberships(socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project_id = socket.assigns.project.id

    {:ok, memberships} =
      Sitevoice.Projects.list_project_memberships(project_id,
        tenant: org_id,
        actor: user,
        authorize?: true
      )

    addable_users =
      if user.role in [:pm, :org_admin, :owner] do
        case Sitevoice.Accounts.list_users(tenant: org_id, actor: user, authorize?: true) do
          {:ok, org_users} ->
            member_ids = MapSet.new(memberships, & &1.user_id)
            Enum.filter(org_users, &(not MapSet.member?(member_ids, &1.id) and &1.active))

          _ ->
            []
        end
      else
        []
      end

    socket
    |> assign(:memberships, memberships)
    |> assign(:addable_users, addable_users)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/projects" />
      <div class="app-page blueprint-bg orange-glow">
        <div style="max-width: 1000px; margin: 0 auto; padding: 40px 24px;">
          <div style="margin-bottom: 32px;">
            <a href={~p"/projects"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
              All Projects
            </a>
            <div style="display: flex; align-items: center; gap: 16px; flex-wrap: wrap; margin-top: 12px;">
              <div class="display-heading" style="font-size: 26px;"><%= @project.name %></div>
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
                <div style="display: flex; gap: 8px;">
                  <a href={~p"/projects/#{@project.id}/logs/today"} class="btn-primary" style="padding: 10px 18px; font-size: 12px;">
                    Today's Log
                  </a>
                  <a href={~p"/projects/#{@project.id}/logs/new"} style="padding: 10px 18px; font-size: 12px; font-family: var(--font-mono); letter-spacing: 1px; text-transform: uppercase; border: 1px solid var(--wire); border-radius: 6px; color: var(--chalk); text-decoration: none; opacity: 0.7; display: inline-flex; align-items: center;">
                    + Quick Submit
                  </a>
                  <a href={~p"/projects/#{@project.id}/weekly-reports"} style="padding: 10px 18px; font-size: 12px; font-family: var(--font-mono); letter-spacing: 1px; text-transform: uppercase; border: 1px solid var(--wire); border-radius: 6px; color: var(--chalk); text-decoration: none; opacity: 0.7; display: inline-flex; align-items: center;">
                    Weekly Reports
                  </a>
                </div>
              </div>
              <div class="card" style="padding: 0; overflow: hidden;">
                <%= if @logs == [] do %>
                  <div class="empty-state" style="padding: 40px 20px;">
                    <div class="empty-state-title" style="font-size: 22px;">No Logs Yet</div>
                    <div class="empty-state-sub">Submit the first recording for this project.</div>
                  </div>
                <% else %>
                  <%= for log <- @logs do %>
                    <a href={log_link(log)} class="row-item" style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-bottom: 1px solid rgba(61,79,101,0.3); text-decoration: none; border-radius: 0;">
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
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="opacity: 0.4; flex-shrink: 0;"><polyline points="9 18 15 12 9 6"/></svg>
                      </div>
                    </a>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Right Column --%>
            <div>

            <%!-- Crew Templates Panel --%>
            <div style="margin-bottom: 24px;">
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
                <div class="section-label" style="margin-bottom: 0;">Crew Templates</div>
                <%= if @current_user.role in [:foreman, :pm, :org_admin] do %>
                  <button class="btn-secondary" style="padding: 6px 12px; font-size: 11px;" phx-click="open_crew_form">+ Add Crew</button>
                <% end %>
              </div>

              <%= if @show_crew_form do %>
                <div class="card" style="margin-bottom: 16px; border-color: var(--orange);">
                  <%= if @crew_error do %>
                    <div class="alert-error" style="margin-bottom: 12px; font-size: 12px;"><%= @crew_error %></div>
                  <% end %>
                  <form phx-submit="add_crew">
                    <div class="form-group">
                      <label class="form-label">Crew Name</label>
                      <input class="form-input" type="text" name="crew[name]" placeholder="e.g. Foundation Crew A" style="font-size: 12px;" required />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Trade</label>
                      <select class="form-select" name="crew[trade]" style="font-size: 12px;">
                        <option value="general">General</option>
                        <option value="concrete">Concrete</option>
                        <option value="framing">Framing</option>
                        <option value="electrical">Electrical</option>
                        <option value="plumbing">Plumbing</option>
                        <option value="steel">Steel</option>
                        <option value="hvac">HVAC</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label class="form-label">Subcontractor</label>
                      <input class="form-input" type="text" name="crew[subcontractor]" placeholder="Company name (optional)" style="font-size: 12px;" />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Default Headcount</label>
                      <input class="form-input" type="number" name="crew[headcount]" min="1" value="1" style="font-size: 12px; width: 80px;" />
                    </div>
                    <div style="display: flex; gap: 8px;">
                      <button type="submit" class="btn-primary" style="padding: 8px 16px; font-size: 12px;">Add</button>
                      <button type="button" class="btn-ghost" style="font-size: 12px; padding: 8px 0;" phx-click="close_crew_form">Cancel</button>
                    </div>
                  </form>
                </div>
              <% end %>

              <div class="card" style="padding: 0; overflow: hidden;">
                <%= if @crew_templates == [] do %>
                  <div style="padding: 20px; color: var(--chalk); opacity: 0.5; font-size: 12px; text-align: center; font-family: var(--font-mono); line-height: 1.6;">
                    No crews yet.<br/>Add crews to pre-fill attendance each day.
                  </div>
                <% else %>
                  <%= for tmpl <- @crew_templates do %>
                    <div style="padding: 12px 16px; border-bottom: 1px solid rgba(61,79,101,0.3); display: flex; align-items: center; gap: 10px;">
                      <div style="flex: 1; min-width: 0;">
                        <div style="font-size: 12px; color: var(--white); font-weight: 500;"><%= tmpl.name %></div>
                        <div style="font-size: 10px; color: var(--chalk); opacity: 0.4; font-family: var(--font-mono); margin-top: 2px;">
                          <%= tmpl.trade %> · <%= tmpl.default_headcount %> workers
                          <%= if tmpl.subcontractor, do: " · #{tmpl.subcontractor}" %>
                        </div>
                      </div>
                      <%= if @current_user.role in [:foreman, :pm, :org_admin] do %>
                        <button
                          phx-click="deactivate_crew"
                          phx-value-id={tmpl.id}
                          style="background: none; border: none; cursor: pointer; color: var(--chalk); opacity: 0.3; padding: 4px; line-height: 1; font-size: 14px;"
                          title="Remove crew template"
                        >✕</button>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Members Panel --%>
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
                      <label class="form-label">User</label>
                      <%= if @addable_users == [] do %>
                        <div style="font-size: 12px; color: var(--chalk); opacity: 0.5;">All org members are already on this project.</div>
                      <% else %>
                        <select class="form-select" name="membership[user_id]" style="font-size: 12px;">
                          <%= for u <- @addable_users do %>
                            <option value={u.id}><%= u.name %> — <%= u.email %></option>
                          <% end %>
                        </select>
                      <% end %>
                    </div>
                    <div class="form-group">
                      <label class="form-label">Project Role</label>
                      <select class="form-select" name="membership[role]" style="font-size: 12px;">
                        <option value="foreman">Foreman</option>
                        <option value="pm">PM</option>
                      </select>
                    </div>
                    <div style="display: flex; gap: 8px;">
                      <%= if @addable_users != [] do %>
                        <button type="submit" class="btn-primary" style="padding: 8px 16px; font-size: 12px;">Add</button>
                      <% end %>
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
                    <div style="padding: 12px 16px; border-bottom: 1px solid rgba(61,79,101,0.3); display: flex; align-items: center; gap: 10px;">
                      <div style={"width: 30px; height: 30px; border-radius: 50%; background: #{member_avatar_color(m.user && m.user.role)}; display: flex; align-items: center; justify-content: center; font-family: var(--font-mono); font-size: 11px; font-weight: 700; color: #EEF1F5; flex-shrink: 0;"}>
                        <%= if m.user, do: String.first(m.user.name) |> String.upcase(), else: "?" %>
                      </div>
                      <div style="flex: 1; min-width: 0;">
                        <div style="font-size: 12px; color: var(--white); font-weight: 500; truncate;">
                          <%= m.user && m.user.name %>
                        </div>
                        <div style="font-size: 10px; color: var(--chalk); opacity: 0.4; font-family: var(--font-mono); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                          <%= m.user && m.user.email %>
                        </div>
                      </div>
                      <%= if @current_user.role in [:org_admin, :owner, :pm] do %>
                        <select
                          class="form-select"
                          style="width: 80px; font-size: 10px; padding: 3px 6px; background: transparent; border-color: rgba(61,79,101,0.4);"
                          phx-change="change_membership_role"
                          phx-value-id={m.id}
                        >
                          <option value="foreman" selected={m.role == :foreman}>Foreman</option>
                          <option value="pm" selected={m.role == :pm}>PM</option>
                          <option value="org_admin" selected={m.role == :org_admin}>Admin</option>
                          <option value="owner" selected={m.role == :owner}>Owner</option>
                        </select>
                        <button
                          phx-click="confirm_remove_member"
                          phx-value-id={m.id}
                          style="background: none; border: none; cursor: pointer; color: #F87171; opacity: 0.6; padding: 4px; line-height: 1;"
                          title="Remove from project"
                        >
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
            </div><%!-- /Right Column --%>
          </div>
        </div>
      </div>

      <%!-- Remove Confirm Dialog --%>
      <%= if @confirm_remove do %>
        <div class="modal-overlay">
          <div class="modal-box" style="max-width: 360px; text-align: center;">
            <div style="font-size: 16px; color: var(--white); font-weight: 600; margin-bottom: 8px;">Remove Member?</div>
            <div style="font-size: 13px; color: var(--chalk); opacity: 0.7; margin-bottom: 24px;">
              This person will lose access to the project's logs.
            </div>
            <div style="display: flex; gap: 10px; justify-content: center;">
              <button
                class="btn-primary"
                style="padding: 10px 20px; font-size: 13px; background: #F87171; border-color: #F87171;"
                phx-click="remove_member"
              >
                Remove
              </button>
              <button class="btn-ghost" phx-click="cancel_remove">Cancel</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
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

  defp member_avatar_color(role) do
    case role do
      :owner -> "#92400E"
      :org_admin -> "#5B21B6"
      :pm -> "#1D4ED8"
      _ -> "#374151"
    end
  end

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)
end
