defmodule SitevoiceWeb.Logs.IndexLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    topic = "org:#{org_id}:logs"
    Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)

    logs = load_logs(org_id, user, nil, nil)

    {:ok,
     socket
     |> assign(:tenant, org_id)
     |> assign(:logs, logs)
     |> assign(:filter_project_id, nil)
     |> assign(:filter_status, nil)}
  end

  @impl true
  def handle_info({:log_updated, log}, socket) do
    logs =
      socket.assigns.logs
      |> Enum.map(fn existing ->
        if existing.id == log.id, do: log, else: existing
      end)

    {:noreply, assign(socket, :logs, logs)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project_id = params["filter"]["project_id"] |> nil_if_blank()
    status = params["filter"]["status"] |> nil_if_blank() |> safe_atom()

    logs = load_logs(org_id, user, project_id, status)

    {:noreply,
     socket
     |> assign(:logs, logs)
     |> assign(:filter_project_id, project_id)
     |> assign(:filter_status, status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_path="/logs" />
      <div class="app-page blueprint-bg orange-glow" style="padding: 40px;">
        <div style="max-width: 1100px; margin: 0 auto;">
        <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
          <div class="section-label">All Logs</div>
          <div class="display-heading">PM Dashboard</div>
        </div>

        <%!-- Filter Bar --%>
        <form phx-change="filter" style="margin-bottom: 24px; display: flex; gap: 16px; flex-wrap: wrap; align-items: flex-end;">
          <div class="form-group" style="margin-bottom: 0;">
            <label class="form-label">Status</label>
            <select class="form-select" name="filter[status]" style="min-width: 150px;">
              <option value="">All Statuses</option>
              <option value="pending" selected={@filter_status == :pending}>Pending</option>
              <option value="processing" selected={@filter_status == :processing}>Processing</option>
              <option value="draft" selected={@filter_status == :draft}>Ready for Review</option>
              <option value="submitted" selected={@filter_status == :submitted}>Submitted</option>
              <option value="failed" selected={@filter_status == :failed}>Failed</option>
            </select>
          </div>
        </form>

        <%!-- Logs Table --%>
        <div class="card" style="padding: 0; overflow: hidden;">
          <table class="data-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Project</th>
                <th>Foreman</th>
                <th>Status</th>
                <th style="text-align: right;">Action</th>
              </tr>
            </thead>
            <tbody>
              <%= if @logs == [] do %>
                <tr>
                  <td colspan="5" style="text-align: center; padding: 40px; color: var(--chalk); opacity: 0.5;">
                    No logs found.
                  </td>
                </tr>
              <% else %>
                <%= for log <- @logs do %>
                  <tr class="tr-link" phx-click={JS.navigate(log_link(log))}>
                    <td><%= Calendar.strftime(log.date, "%b %d, %Y") %></td>
                    <td>
                      <span style="font-family: var(--font-mono); font-size: 12px; color: var(--orange);">
                        <%= log.project && log.project.code %>
                      </span>
                    </td>
                    <td style="color: var(--chalk); opacity: 0.8;">
                      <%= log.foreman && log.foreman.name %>
                    </td>
                    <td><.log_status_pill status={log.status} /></td>
                    <td style="text-align: right;">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="opacity: 0.4;"><polyline points="9 18 15 12 9 6"/></svg>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
        </div>
      </div>
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

  defp load_logs(org_id, user, project_id, status) do
    case Sitevoice.Reporting.list_logs(project_id, status,
           tenant: org_id,
           actor: user,
           authorize?: true,
           load: [:foreman, :project]
         ) do
      {:ok, logs} -> logs
      {:error, reason} ->
        require Logger
        Logger.error("IndexLive failed to load logs for org=#{org_id}: #{inspect(reason)}")
        []
    end
  end

  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(""), do: nil
  defp nil_if_blank(val), do: val

  defp safe_atom(nil), do: nil
  defp safe_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> nil
    end
  end

  defp log_link(log) do
    case log.status do
      s when s in [:processing, :pending] -> ~p"/logs/#{log.id}/processing"
      _ -> ~p"/logs/#{log.id}"
    end
  end
end
