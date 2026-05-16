defmodule SitevoiceWeb.Settings.OrganizationLive do
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
      {:ok, org} = load_org(org_id, user)
      {:ok, member_count} = load_member_count(org_id, user)

      {:ok,
       socket
       |> assign(:tenant, org_id)
       |> assign(:org, org)
       |> assign(:member_count, member_count)
       |> assign(:org_error, nil)}
    end
  end

  @impl true
  def handle_event("save_org", %{"org" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    org = socket.assigns.org

    case Ash.update(org, %{name: params["name"]},
           action: :update,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:org, updated)
         |> assign(:org_error, nil)
         |> put_flash(:info, "Organization updated.")}

      {:error, error} ->
        {:noreply, assign(socket, :org_error, format_error(error))}
    end
  end

  defp load_org(org_id, actor) do
    Ash.get(Sitevoice.Accounts.Organization, org_id,
      tenant: org_id,
      actor: actor,
      authorize?: true
    )
  end

  defp load_member_count(org_id, actor) do
    case Sitevoice.Accounts.list_users(tenant: org_id, actor: actor, authorize?: true) do
      {:ok, users} -> {:ok, length(users)}
      _ -> {:ok, 0}
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
      <div class="app-page blueprint-bg orange-glow ">
        <div style="display: flex; gap: 48px; align-items: flex-start; max-width: 1100px; margin: 0 auto; min-height: calc(100vh - 72px); padding: 40px 24px;">
          <.settings_nav current="org" current_user={@current_user} />

          <div style="flex: 1; min-width: 0;">
            <div style="margin-bottom: 28px;">
              <div class="display-heading" style="font-size: 26px;">Organization</div>
            </div>

            <%!-- Org Info Card --%>
            <div class="card" style="margin-bottom: 24px;">
              <div style="display: flex; gap: 20px; align-items: center; margin-bottom: 24px;">
                <div style="width: 56px; height: 56px; border-radius: 10px; background: rgba(255,92,0,0.15); border: 1px solid rgba(255,92,0,0.3); display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-size: 22px; color: var(--orange);">
                  {String.first(@org.name) |> String.upcase()}
                </div>
                <div>
                  <div style="font-size: 18px; color: var(--white); font-weight: 600;">
                    {@org.name}
                  </div>
                  <div style="font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5; margin-top: 4px; text-transform: uppercase; letter-spacing: 1px;">
                    {@member_count} members · <span style="color: var(--orange);">{@org.tier}</span>
                  </div>
                </div>
              </div>

              <div class="section-label">Settings</div>
              <%= if @org_error do %>
                <div class="alert-error" style="margin-bottom: 16px; font-size: 13px;">
                  {@org_error}
                </div>
              <% end %>
              <form phx-submit="save_org">
                <div class="form-group">
                  <label class="form-label">Organization Name</label>
                  <input class="form-input" type="text" name="org[name]" value={@org.name} required />
                </div>
                <div class="form-group">
                  <label class="form-label">Slug</label>
                  <input
                    class="form-input"
                    type="text"
                    value={@org.slug}
                    disabled
                    style="opacity: 0.4; cursor: not-allowed; font-family: var(--font-mono);"
                  />
                  <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; margin-top: 4px; text-transform: uppercase; letter-spacing: 1px;">
                    Slug cannot be changed
                  </div>
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

            <%!-- Stats Card --%>
            <div class="card">
              <div class="section-label">Overview</div>
              <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 8px;">
                <div style="background: rgba(61,79,101,0.2); border: 1px solid rgba(61,79,101,0.3); border-radius: 6px; padding: 16px;">
                  <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">
                    Members
                  </div>
                  <div style="font-size: 28px; color: var(--white); font-weight: 700;">
                    {@member_count}
                  </div>
                </div>
                <div style="background: rgba(61,79,101,0.2); border: 1px solid rgba(61,79,101,0.3); border-radius: 6px; padding: 16px;">
                  <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">
                    Plan
                  </div>
                  <div style="font-size: 16px; color: var(--orange); font-family: var(--font-mono); text-transform: uppercase; letter-spacing: 2px; font-weight: 700; margin-top: 6px;">
                    {@org.tier}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
