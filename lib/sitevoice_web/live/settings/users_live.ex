defmodule SitevoiceWeb.Settings.UsersLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role not in [:org_admin, :owner] do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      org_id = to_string(user.organization_id)
      users = load_users(org_id, user)

      {:ok,
       socket
       |> assign(:tenant, org_id)
       |> assign(:users, users)
       |> assign(:filtered_users, users)
       |> assign(:show_invite_modal, false)
       |> assign(:invite_error, nil)
       |> assign(:search, "")
       |> assign(:filter_role, "all")
       |> assign(:filter_status, "all")
       |> assign(:confirm_action, nil)}
    end
  end

  @impl true
  def handle_event("open_invite", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: true, invite_error: nil)}
  end

  def handle_event("close_invite", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: false, invite_error: nil)}
  end

  def handle_event("invite", %{"user" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    input = %{
      email: params["email"],
      name: params["name"],
      role: String.to_existing_atom(params["role"]),
      preferred_language: String.to_existing_atom(params["language"] || "en")
    }

    case Sitevoice.Accounts.invite_user(input, tenant: org_id, actor: user, authorize?: true) do
      {:ok, _new_user} ->
        users = load_users(org_id, user)

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:filtered_users, apply_filters(users, socket.assigns))
         |> assign(:show_invite_modal, false)
         |> assign(:invite_error, nil)
         |> put_flash(:info, "Invitation sent.")}

      {:error, error} ->
        {:noreply, assign(socket, :invite_error, format_error(error))}
    end
  end

  def handle_event("resend_invite", %{"id" => user_id}, socket) do
    _user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    target = Enum.find(socket.assigns.users, &(to_string(&1.id) == user_id))

    if target do
      Ash.ActionInput.for_action(
        Sitevoice.Accounts.User,
        :request_password_reset_token,
        %{email: target.email},
        authorize?: false,
        tenant: org_id
      )
      |> Ash.run_action!()

      {:noreply, put_flash(socket, :info, "Invitation resent to #{target.email}.")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_action", %{"action" => action, "id" => id}, socket) do
    {:noreply, assign(socket, :confirm_action, %{action: action, id: id})}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  def handle_event("execute_confirm", _params, socket) do
    %{action: action, id: id} = socket.assigns.confirm_action
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    target = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))

    result =
      case action do
        "deactivate" ->
          Sitevoice.Accounts.deactivate_user(target,
            tenant: org_id,
            actor: user,
            authorize?: true
          )

        "reactivate" ->
          Sitevoice.Accounts.reactivate_user(target,
            tenant: org_id,
            actor: user,
            authorize?: true
          )
      end

    case result do
      {:ok, _} ->
        users = load_users(org_id, user)

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:filtered_users, apply_filters(users, socket.assigns))
         |> assign(:confirm_action, nil)
         |> put_flash(:info, "User updated.")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(:confirm_action, nil)
         |> put_flash(:error, format_error(error))}
    end
  end

  def handle_event("change_role", %{"id" => id, "role" => role}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    target = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))

    case Sitevoice.Accounts.update_user_role(target, %{role: String.to_existing_atom(role)},
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _} ->
        users = load_users(org_id, user)

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:filtered_users, apply_filters(users, socket.assigns))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, format_error(error))}
    end
  end

  def handle_event("filter", %{"search" => search, "role" => role, "status" => status}, socket) do
    filters = %{socket.assigns | search: search, filter_role: role, filter_status: status}
    filtered = apply_filters(socket.assigns.users, filters)

    {:noreply,
     assign(socket,
       search: search,
       filter_role: role,
       filter_status: status,
       filtered_users: filtered
     )}
  end

  defp load_users(org_id, actor) do
    case Sitevoice.Accounts.list_users(tenant: org_id, actor: actor, authorize?: true) do
      {:ok, users} -> Enum.sort_by(users, & &1.inserted_at, {:desc, DateTime})
      _ -> []
    end
  end

  defp apply_filters(users, assigns) do
    users
    |> filter_by_search(assigns.search)
    |> filter_by_role(assigns.filter_role)
    |> filter_by_status(assigns.filter_status)
  end

  defp filter_by_search(users, ""), do: users

  defp filter_by_search(users, search) do
    q = String.downcase(search)

    Enum.filter(users, fn u ->
      String.contains?(String.downcase(u.name), q) or
        String.contains?(String.downcase(to_string(u.email)), q)
    end)
  end

  defp filter_by_role(users, "all"), do: users
  defp filter_by_role(users, role), do: Enum.filter(users, &(to_string(&1.role) == role))

  defp filter_by_status(users, "all"), do: users
  defp filter_by_status(users, "active"), do: Enum.filter(users, & &1.active)
  defp filter_by_status(users, "deactivated"), do: Enum.filter(users, &(not &1.active))

  defp filter_by_status(users, "pending"),
    do: Enum.filter(users, &(not is_nil(&1.invited_at) and is_nil(&1.confirmed_at)))

  defp user_status(user) do
    cond do
      not user.active -> :deactivated
      not is_nil(user.invited_at) and is_nil(user.confirmed_at) -> :pending
      true -> :active
    end
  end

  defp format_error(%Ash.Error.Invalid{errors: errors}),
    do: errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")

  defp format_error(%{message: msg}), do: msg
  defp format_error(error), do: inspect(error)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/settings" />
      <div class="app-page blueprint-bg orange-glow">
        <div style="display: flex; gap: 48px; align-items: flex-start; max-width: 1100px; margin: 0 auto; min-height: calc(100vh - 72px); padding: 40px 24px;">
          <.settings_nav current="users" current_user={@current_user} />

          <div style="flex: 1; min-width: 0;">
            <%!-- Header --%>
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; flex-wrap: wrap; gap: 12px;">
              <div>
                <div class="display-heading" style="font-size: 26px;">Users</div>
                <div style="font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 1px; margin-top: 4px;">
                  {length(@users)} members
                </div>
              </div>
              <button
                class="btn-primary"
                style="padding: 10px 20px; font-size: 12px;"
                phx-click="open_invite"
              >
                + Invite User
              </button>
            </div>

            <%!-- Filter Bar --%>
            <form
              phx-change="filter"
              style="display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px;"
            >
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Search by name or email..."
                class="form-input"
                style="flex: 1; min-width: 200px; font-size: 13px;"
                phx-debounce="200"
              />
              <select name="role" class="form-select" style="width: 140px; font-size: 13px;">
                <option value="all" selected={@filter_role == "all"}>All Roles</option>
                <option value="owner" selected={@filter_role == "owner"}>Owner</option>
                <option value="org_admin" selected={@filter_role == "org_admin"}>Admin</option>
                <option value="pm" selected={@filter_role == "pm"}>PM</option>
                <option value="foreman" selected={@filter_role == "foreman"}>Foreman</option>
              </select>
              <select name="status" class="form-select" style="width: 140px; font-size: 13px;">
                <option value="all" selected={@filter_status == "all"}>All Status</option>
                <option value="active" selected={@filter_status == "active"}>Active</option>
                <option value="pending" selected={@filter_status == "pending"}>Pending</option>
                <option value="deactivated" selected={@filter_status == "deactivated"}>
                  Deactivated
                </option>
              </select>
            </form>

            <%!-- Users Table --%>
            <div class="card" style="padding: 0; overflow: hidden;">
              <%= if @filtered_users == [] do %>
                <div class="empty-state" style="padding: 48px 24px;">
                  <div class="empty-state-title" style="font-size: 20px;">No Users Found</div>
                  <div class="empty-state-sub">Try adjusting your filters or invite someone new.</div>
                </div>
              <% else %>
                <table style="width: 100%; border-collapse: collapse;">
                  <thead>
                    <tr style="border-bottom: 1px solid rgba(61,79,101,0.5);">
                      <th style="padding: 12px 20px; text-align: left; font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 2px; font-weight: 400;">
                        User
                      </th>
                      <th style="padding: 12px 16px; text-align: left; font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 2px; font-weight: 400;">
                        Role
                      </th>
                      <th style="padding: 12px 16px; text-align: left; font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 2px; font-weight: 400;">
                        Status
                      </th>
                      <th style="padding: 12px 16px; text-align: left; font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 2px; font-weight: 400;">
                        Joined
                      </th>
                      <th style="padding: 12px 20px; text-align: right; font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 2px; font-weight: 400;">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for u <- @filtered_users do %>
                      <tr style="border-bottom: 1px solid rgba(61,79,101,0.2);" class="row-item">
                        <td style="padding: 14px 20px;">
                          <div style="display: flex; align-items: center; gap: 12px;">
                            <div style={"width: 36px; height: 36px; border-radius: 50%; background: #{avatar_color(u.role)}; display: flex; align-items: center; justify-content: center; font-family: var(--font-mono); font-size: 13px; font-weight: 700; color: #EEF1F5; flex-shrink: 0;"}>
                              {String.first(u.name) |> String.upcase()}
                            </div>
                            <div>
                              <div style="font-size: 14px; color: var(--white); font-weight: 500;">
                                {u.name}
                                <%= if u.id == @current_user.id do %>
                                  <span style="font-family: var(--font-mono); font-size: 9px; color: var(--orange); text-transform: uppercase; letter-spacing: 1px; margin-left: 6px; opacity: 0.8;">
                                    you
                                  </span>
                                <% end %>
                              </div>
                              <div style="font-size: 12px; color: var(--chalk); opacity: 0.5; font-family: var(--font-mono);">
                                {u.email}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td style="padding: 14px 16px;">
                          <%= if @current_user.role in [:org_admin, :owner] and u.id != @current_user.id do %>
                            <select
                              class="form-select"
                              style="width: 110px; font-size: 12px; padding: 4px 8px; background: transparent; border-color: rgba(61,79,101,0.5);"
                              phx-change="change_role"
                              phx-value-id={u.id}
                            >
                              <option value="foreman" selected={u.role == :foreman}>Foreman</option>
                              <option value="pm" selected={u.role == :pm}>PM</option>
                              <option value="org_admin" selected={u.role == :org_admin}>Admin</option>
                              <option value="owner" selected={u.role == :owner}>Owner</option>
                            </select>
                          <% else %>
                            <.role_badge role={u.role} />
                          <% end %>
                        </td>
                        <td style="padding: 14px 16px;">
                          <.status_badge status={user_status(u)} />
                        </td>
                        <td style="padding: 14px 16px; font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5;">
                          {if u.invited_at,
                            do: format_date(u.invited_at),
                            else: format_date(u.inserted_at)}
                        </td>
                        <td style="padding: 14px 20px; text-align: right;">
                          <div style="display: flex; align-items: center; justify-content: flex-end; gap: 8px;">
                            <%= if user_status(u) == :pending do %>
                              <button
                                class="btn-ghost"
                                style="font-size: 11px; padding: 4px 10px; color: var(--chalk); opacity: 0.7;"
                                phx-click="resend_invite"
                                phx-value-id={u.id}
                              >
                                Resend
                              </button>
                            <% end %>
                            <%= if u.id != @current_user.id do %>
                              <%= if u.active do %>
                                <button
                                  class="btn-ghost"
                                  style="font-size: 11px; padding: 4px 10px; color: #F87171;"
                                  phx-click="confirm_action"
                                  phx-value-action="deactivate"
                                  phx-value-id={u.id}
                                >
                                  Deactivate
                                </button>
                              <% else %>
                                <button
                                  class="btn-ghost"
                                  style="font-size: 11px; padding: 4px 10px; color: #34D399;"
                                  phx-click="confirm_action"
                                  phx-value-action="reactivate"
                                  phx-value-id={u.id}
                                >
                                  Reactivate
                                </button>
                              <% end %>
                            <% end %>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              <% end %>
            </div>
            <%!-- users table card --%>
          </div>
          <%!-- flex: 1 content --%>
        </div>
        <%!-- flex container --%>
      </div>
      <%!-- app-page --%>

      <%!-- Invite Modal --%>
      <%= if @show_invite_modal do %>
        <div class="modal-overlay" phx-click="close_invite">
          <div
            class="modal-box"
            phx-click-away="close_invite"
            style="max-width: 460px;"
            onclick="event.stopPropagation()"
          >
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px;">
              <div class="section-label" style="margin-bottom: 0;">Invite User</div>
              <button
                class="btn-ghost"
                style="font-size: 18px; opacity: 0.5; padding: 0;"
                phx-click="close_invite"
              >
                ×
              </button>
            </div>
            <%= if @invite_error do %>
              <div class="alert-error" style="margin-bottom: 16px; font-size: 13px;">
                {@invite_error}
              </div>
            <% end %>
            <form phx-submit="invite">
              <div class="form-group">
                <label class="form-label">Name</label>
                <input
                  class="form-input"
                  type="text"
                  name="user[name]"
                  placeholder="Full name"
                  required
                />
              </div>
              <div class="form-group">
                <label class="form-label">Email</label>
                <input
                  class="form-input"
                  type="email"
                  name="user[email]"
                  placeholder="email@company.com"
                  required
                />
              </div>
              <div class="form-group">
                <label class="form-label">Role</label>
                <select class="form-select" name="user[role]">
                  <option value="foreman">Foreman — submits daily logs</option>
                  <option value="pm">PM — reviews and approves logs</option>
                  <option value="org_admin">Admin — manages users and projects</option>
                </select>
              </div>
              <div class="form-group">
                <label class="form-label">Language</label>
                <select class="form-select" name="user[language]">
                  <option value="en">English</option>
                  <option value="es">Español</option>
                </select>
              </div>
              <div style="display: flex; gap: 10px; margin-top: 24px;">
                <button
                  type="submit"
                  class="btn-primary"
                  style="flex: 1; padding: 12px; font-size: 13px;"
                >
                  Send Invitation
                </button>
                <button type="button" class="btn-ghost" phx-click="close_invite">Cancel</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <%!-- Confirm Dialog --%>
      <%= if @confirm_action do %>
        <div class="modal-overlay">
          <div class="modal-box" style="max-width: 380px; text-align: center;">
            <div style="font-size: 32px; margin-bottom: 16px;">
              {if @confirm_action.action == "deactivate", do: "⚠️", else: "✓"}
            </div>
            <div style="font-size: 16px; color: var(--white); font-weight: 600; margin-bottom: 8px;">
              {if @confirm_action.action == "deactivate",
                do: "Deactivate User?",
                else: "Reactivate User?"}
            </div>
            <div style="font-size: 13px; color: var(--chalk); opacity: 0.7; margin-bottom: 24px;">
              <%= if @confirm_action.action == "deactivate" do %>
                This user will no longer be able to sign in. You can reactivate them at any time.
              <% else %>
                This user will regain access to sign in.
              <% end %>
            </div>
            <div style="display: flex; gap: 10px; justify-content: center;">
              <button
                class="btn-primary"
                style={"padding: 10px 20px; font-size: 13px; #{if @confirm_action.action == "deactivate", do: "background: #F87171; border-color: #F87171;", else: ""}"}
                phx-click="execute_confirm"
              >
                {if @confirm_action.action == "deactivate", do: "Deactivate", else: "Reactivate"}
              </button>
              <button class="btn-ghost" phx-click="cancel_confirm">Cancel</button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    <%!-- app-ui --%>
    """
  end

  defp role_badge(assigns) do
    {color, label} =
      case assigns.role do
        :owner -> {"#F59E0B", "Owner"}
        :org_admin -> {"#A78BFA", "Admin"}
        :pm -> {"#60A5FA", "PM"}
        :foreman -> {"#6B7280", "Foreman"}
        _ -> {"#6B7280", to_string(assigns.role)}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span style={"font-family: var(--font-mono); font-size: 10px; color: #{@color}; background: #{@color}22; border: 1px solid #{@color}44; padding: 3px 8px; border-radius: 3px; text-transform: uppercase; letter-spacing: 1px; white-space: nowrap;"}>
      {@label}
    </span>
    """
  end

  defp status_badge(assigns) do
    {color, label} =
      case assigns.status do
        :active -> {"#22C55E", "Active"}
        :pending -> {"#F59E0B", "Pending"}
        :deactivated -> {"#F87171", "Deactivated"}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span style={"font-family: var(--font-mono); font-size: 10px; color: #{@color}; background: #{@color}22; border: 1px solid #{@color}44; padding: 3px 8px; border-radius: 3px; text-transform: uppercase; letter-spacing: 1px;"}>
      {@label}
    </span>
    """
  end

  defp avatar_color(role) do
    case role do
      :owner -> "#92400E"
      :org_admin -> "#5B21B6"
      :pm -> "#1D4ED8"
      _ -> "#374151"
    end
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(_), do: "—"
end
