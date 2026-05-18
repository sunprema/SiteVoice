defmodule SitevoiceWeb.Projects.SettingsLive do
  @moduledoc """
  Project settings page focused on the daily-log brief: which canonical
  sections the project requires, the free-text project context, and the
  per-project minimum accuracy threshold for triggering clarifications.
  """

  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  require Logger

  @all_sections [:labor, :progress, :equipment, :materials, :delays, :safety, :weather]

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    case Sitevoice.Projects.get_project(project_id, tenant: org_id, actor: user, authorize?: true) do
      {:ok, project} ->
        socket =
          socket
          |> assign(:tenant, org_id)
          |> assign(:project, project)
          |> assign(:required_sections, project.required_sections || [])
          |> assign(:daily_log_context, project.daily_log_context || "")
          |> assign(:min_accuracy, project.daily_log_min_accuracy || 0.7)
          |> assign(:all_sections, @all_sections)
          |> assign(:error, nil)
          |> assign(:saved?, false)

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section_str}, socket) do
    section = String.to_existing_atom(section_str)
    current = socket.assigns.required_sections

    updated =
      if section in current do
        List.delete(current, section)
      else
        [section | current]
      end

    {:noreply, assign(socket, :required_sections, updated)}
  end

  def handle_event("validate", %{"brief" => params}, socket) do
    {:noreply,
     socket
     |> assign(:daily_log_context, params["daily_log_context"] || socket.assigns.daily_log_context)
     |> assign(:min_accuracy, parse_float(params["min_accuracy"], socket.assigns.min_accuracy))
     |> assign(:saved?, false)}
  end

  def handle_event("save", %{"brief" => params}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    attrs = %{
      required_sections: socket.assigns.required_sections,
      daily_log_context: params["daily_log_context"] || socket.assigns.daily_log_context,
      daily_log_min_accuracy: parse_float(params["min_accuracy"], socket.assigns.min_accuracy)
    }

    case Ash.update(project, attrs,
           action: :update_daily_log_brief,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:project, updated)
         |> assign(:required_sections, updated.required_sections || [])
         |> assign(:daily_log_context, updated.daily_log_context || "")
         |> assign(:min_accuracy, updated.daily_log_min_accuracy || 0.7)
         |> assign(:saved?, true)
         |> assign(:error, nil)}

      {:error, error} ->
        Logger.error("SettingsLive save failed: #{inspect(error)}")
        {:noreply, assign(socket, :error, format_error(error))}
    end
  end

  defp parse_float(nil, fallback), do: fallback
  defp parse_float("", fallback), do: fallback

  defp parse_float(val, fallback) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> max(0.0, min(1.0, f))
      :error -> fallback
    end
  end

  defp parse_float(val, _) when is_float(val), do: val
  defp parse_float(val, _) when is_integer(val), do: val * 1.0
  defp parse_float(_, fallback), do: fallback

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/projects" />
      <div class="app-page blueprint-bg">
        <div style="max-width: 720px; margin: 0 auto; padding: 40px 24px;">
          <div style="margin-bottom: 28px;">
            <a href={~p"/projects/#{@project.id}"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
              <%= @project.name %>
            </a>
            <div class="section-label" style="margin-top: 12px;">Project Settings</div>
            <div class="display-heading" style="font-size: 26px;">Daily-Log Brief</div>
            <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-top: 8px;">
              Tell the AI what a complete daily log looks like for this project. The brief shapes
              both extraction and clarification questions.
            </div>
          </div>

          <%= if @saved? do %>
            <div class="alert-success" style="margin-bottom: 20px;">Settings saved.</div>
          <% end %>

          <%= if @error do %>
            <div class="alert-error" style="margin-bottom: 20px;"><%= @error %></div>
          <% end %>

          <form phx-submit="save" phx-change="validate">
            <div class="card" style="margin-bottom: 20px;">
              <div class="section-label">Required Sections</div>
              <div style="font-size: 12px; color: var(--chalk); opacity: 0.6; margin-bottom: 14px;">
                If any of these sections come back empty, we'll ask the foreman for a quick voice follow-up.
              </div>
              <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 8px;">
                <%= for section <- @all_sections do %>
                  <button
                    type="button"
                    phx-click="toggle_section"
                    phx-value-section={Atom.to_string(section)}
                    style={"padding: 10px 12px; font-family: var(--font-mono); font-size: 11px; letter-spacing: 1px; text-transform: uppercase; border-radius: 6px; cursor: pointer; transition: all 0.2s; border: 1px solid #{if section in @required_sections, do: "var(--orange)", else: "var(--wire)"}; background: #{if section in @required_sections, do: "rgba(255,140,0,0.15)", else: "transparent"}; color: #{if section in @required_sections, do: "var(--orange)", else: "var(--chalk)"};"}
                  >
                    <%= Atom.to_string(section) %>
                  </button>
                <% end %>
              </div>
            </div>

            <div class="card" style="margin-bottom: 20px;">
              <div class="section-label">Project Context</div>
              <div style="font-size: 12px; color: var(--chalk); opacity: 0.6; margin-bottom: 12px;">
                A short brief that tells the AI what's special about this site (~1000 chars).
              </div>
              <textarea
                name="brief[daily_log_context]"
                maxlength="1000"
                style="width: 100%; min-height: 140px; background: var(--ink); border: 1px solid var(--wire); border-radius: 6px; color: var(--chalk); font-size: 14px; line-height: 1.6; padding: 14px; resize: vertical; font-family: var(--font-sans); box-sizing: border-box; outline: none;"
                phx-debounce="300"
              ><%= @daily_log_context %></textarea>
              <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; margin-top: 6px;">
                <%= String.length(@daily_log_context) %> / 1000
              </div>
            </div>

            <div class="card" style="margin-bottom: 24px;">
              <div class="section-label">Minimum Accuracy Threshold</div>
              <div style="font-size: 12px; color: var(--chalk); opacity: 0.6; margin-bottom: 12px;">
                When Claude's self-rated accuracy falls below this number, we ask for clarification (0.0–1.0).
              </div>
              <input
                type="number"
                name="brief[min_accuracy]"
                value={@min_accuracy}
                min="0.0"
                max="1.0"
                step="0.05"
                class="form-input"
                style="max-width: 140px;"
              />
            </div>

            <button type="submit" class="btn-primary">Save Brief</button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
