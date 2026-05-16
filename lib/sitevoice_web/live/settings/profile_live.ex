defmodule SitevoiceWeb.Settings.ProfileLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    {:ok,
     socket
     |> assign(:tenant, org_id)
     |> assign(:profile_error, nil)
     |> assign(:password_error, nil)
     |> assign(:profile_saved, false)
     |> assign(:password_saved, false)}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    input = %{
      name: params["name"],
      preferred_language: String.to_existing_atom(params["preferred_language"] || "en")
    }

    case Sitevoice.Accounts.update_profile(user, input,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:profile_saved, true)
         |> assign(:profile_error, nil)
         |> put_flash(:info, "Profile updated.")}

      {:error, error} ->
        {:noreply, assign(socket, profile_error: format_error(error), profile_saved: false)}
    end
  end

  def handle_event("save_password", %{"password" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    input = %{
      current_password: params["current_password"],
      password: params["password"],
      password_confirmation: params["password_confirmation"]
    }

    case Sitevoice.Accounts.change_password(user, input,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:password_saved, true)
         |> assign(:password_error, nil)
         |> put_flash(:info, "Password changed.")}

      {:error, error} ->
        {:noreply, assign(socket, password_error: format_error(error), password_saved: false)}
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
        <div style="display: flex; gap: 48px; align-items: flex-start; max-width: 960px; margin: 0 auto;">
          <.settings_nav current="profile" current_user={@current_user} />

          <div style="flex: 1; min-width: 0; animation: fadeUp 0.5s ease both;">
            <div style="margin-bottom: 28px;">
              <div class="display-heading" style="font-size: 26px;">My Profile</div>
            </div>

            <%!-- Profile Card --%>
            <div class="card" style="margin-bottom: 24px; animation: fadeUp 0.5s ease 0.1s both;">
              <div class="section-label">Account Details</div>
              <%= if @profile_error do %>
                <div class="alert-error" style="margin-bottom: 16px; font-size: 13px;">
                  {@profile_error}
                </div>
              <% end %>
              <form phx-submit="save_profile">
                <div class="form-group">
                  <label class="form-label">Name</label>
                  <input
                    class="form-input"
                    type="text"
                    name="profile[name]"
                    value={@current_user.name}
                    required
                  />
                </div>
                <div class="form-group">
                  <label class="form-label">Email</label>
                  <input
                    class="form-input"
                    type="email"
                    value={@current_user.email}
                    disabled
                    style="opacity: 0.4; cursor: not-allowed;"
                  />
                  <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; margin-top: 4px; text-transform: uppercase; letter-spacing: 1px;">
                    Email cannot be changed
                  </div>
                </div>
                <div class="form-group">
                  <label class="form-label">Role</label>
                  <div style="font-family: var(--font-mono); font-size: 12px; color: var(--orange); text-transform: uppercase; letter-spacing: 2px; margin-top: 4px;">
                    {@current_user.role}
                  </div>
                </div>
                <div class="form-group">
                  <label class="form-label">Preferred Language</label>
                  <select class="form-select" name="profile[preferred_language]">
                    <option value="en" selected={@current_user.preferred_language == :en}>
                      English
                    </option>
                    <option value="es" selected={@current_user.preferred_language == :es}>
                      Español
                    </option>
                  </select>
                </div>
                <button
                  type="submit"
                  class="btn-primary"
                  style="padding: 10px 24px; font-size: 13px; margin-top: 8px;"
                >
                  Save Changes
                </button>
              </form>
            </div>

            <%!-- Password Card --%>
            <div class="card" style="animation: fadeUp 0.5s ease 0.2s both;">
              <div class="section-label">Change Password</div>
              <%= if @password_error do %>
                <div class="alert-error" style="margin-bottom: 16px; font-size: 13px;">
                  {@password_error}
                </div>
              <% end %>
              <form phx-submit="save_password">
                <div class="form-group">
                  <label class="form-label">Current Password</label>
                  <input
                    class="form-input"
                    type="password"
                    name="password[current_password]"
                    required
                    autocomplete="current-password"
                  />
                </div>
                <div class="form-group">
                  <label class="form-label">New Password</label>
                  <input
                    class="form-input"
                    type="password"
                    name="password[password]"
                    required
                    autocomplete="new-password"
                    minlength="8"
                  />
                </div>
                <div class="form-group">
                  <label class="form-label">Confirm New Password</label>
                  <input
                    class="form-input"
                    type="password"
                    name="password[password_confirmation]"
                    required
                    autocomplete="new-password"
                  />
                </div>
                <button
                  type="submit"
                  class="btn-primary"
                  style="padding: 10px 24px; font-size: 13px; margin-top: 8px;"
                >
                  Update Password
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
