defmodule SitevoiceWeb.DashboardLive do
  use SitevoiceWeb, :live_view

  require Logger

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)
    socket = assign(socket, :tenant, org_id)

    socket =
      case user.role do
        role when role in [:foreman] ->
          load_foreman_data(socket, user, org_id)

        _ ->
          load_pm_data(socket, org_id)
      end

    {:ok, socket}
  end

  defp load_foreman_data(socket, user, org_id) do
    today = Date.utc_today()

    today_log =
      case Sitevoice.Reporting.get_today_log_for_foreman(user.id, today,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:pdf_url]
           ) do
        {:ok, log} -> log
        {:error, reason} ->
          Logger.error("DashboardLive failed to load today's log for foreman=#{user.id}: #{inspect(reason)}")
          nil
      end

    recent_logs =
      case Sitevoice.Reporting.list_logs_for_foreman(user.id,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:pdf_url]
           ) do
        {:ok, logs} -> Enum.take(logs, 5)
        {:error, reason} ->
          Logger.error("DashboardLive failed to load recent logs for foreman=#{user.id}: #{inspect(reason)}")
          []
      end

    assign(socket,
      view: :foreman,
      today_log: today_log,
      recent_logs: recent_logs
    )
  end

  defp load_pm_data(socket, org_id) do
    user = socket.assigns.current_user
    today = Date.utc_today()

    all_logs =
      case Sitevoice.Reporting.list_logs_for_date(today,
             tenant: org_id,
             actor: user,
             authorize?: true
           ) do
        {:ok, logs} -> logs
        {:error, reason} ->
          Logger.error("DashboardLive failed to load PM logs for org=#{org_id}: #{inspect(reason)}")
          []
      end

    counts = Enum.frequencies_by(all_logs, & &1.status)

    assign(socket,
      view: :pm,
      today_counts: counts,
      today_total: length(all_logs)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_path="/dashboard" />
      <div class="app-page blueprint-bg orange-glow" style="padding: 40px;">
        <%= if @view == :foreman do %>
          <.foreman_view {assigns} />
        <% else %>
          <.pm_view {assigns} />
        <% end %>
      </div>
    </div>
    """
  end

  defp foreman_view(assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto;">
      <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
        <div class="section-label">Welcome Back</div>
        <div class="display-heading"><%= greeting() %>, <%= first_name(@current_user.name) %></div>
        <div style="font-family: var(--font-mono); font-size: 12px; color: var(--chalk); opacity: 0.5; margin-top: 8px; text-transform: uppercase; letter-spacing: 1px;">
          <%= @current_user.role %> · <%= Date.utc_today() |> Calendar.strftime("%B %d, %Y") %>
        </div>
      </div>

      <%!-- Today's Log Card --%>
      <div class="card" style="margin-bottom: 24px;">
        <div class="section-label">Today's Report</div>
        <%= if @today_log do %>
          <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;">
            <div>
              <div style="font-size: 14px; color: var(--chalk); margin-bottom: 8px;">
                <%= Calendar.strftime(@today_log.date, "%A, %B %d") %>
              </div>
              <.status_pill status={@today_log.status} />
            </div>
            <%= if @today_log.status in [:draft] do %>
              <a href={~p"/logs/#{@today_log.id}"} class="btn-primary" style="padding: 10px 20px; font-size: 13px;">
                Review Report →
              </a>
            <% end %>
            <%= if @today_log.status in [:processing, :pending] do %>
              <a href={~p"/logs/#{@today_log.id}/processing"} class="btn-ghost">
                View Progress →
              </a>
            <% end %>
          </div>
        <% else %>
          <div style="color: var(--chalk); opacity: 0.6; font-size: 14px; margin-bottom: 16px;">
            No report submitted today yet.
          </div>
          <a href={~p"/projects"} class="btn-primary">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="16"/><line x1="8" y1="12" x2="16" y2="12"/></svg>
            RECORD DAY
          </a>
        <% end %>
      </div>

      <%!-- Stats Row --%>
      <div class="stats-row" style="margin-bottom: 32px;">
        <div class="stat-card">
          <div class="stat-num"><%= length(@recent_logs) %></div>
          <div class="stat-label">Recent Reports</div>
        </div>
        <div class="stat-card">
          <div class="stat-num" style="font-size: 28px; color: var(--green);">
            <%= if @today_log && @today_log.status == :submitted, do: "✓", else: "—" %>
          </div>
          <div class="stat-label">Today Submitted</div>
        </div>
      </div>

      <%!-- Recent Reports --%>
      <div class="card">
        <div class="section-label">Recent Reports</div>
        <%= if @recent_logs == [] do %>
          <div class="empty-state">
            <div class="empty-state-title">No Reports Yet</div>
            <div class="empty-state-sub">Submit your first recording to get started.</div>
          </div>
        <% else %>
          <div style="display: flex; flex-direction: column; gap: 0;">
            <%= for log <- @recent_logs do %>
              <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 0; border-bottom: 1px solid rgba(61,79,101,0.3);">
                <div>
                  <div style="font-size: 14px; color: var(--white); margin-bottom: 4px;">
                    <%= Calendar.strftime(log.date, "%B %d, %Y") %>
                  </div>
                  <.status_pill status={log.status} />
                </div>
                <a href={log_link(log)} class="chevron-link">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 18 15 12 9 6"/></svg>
                </a>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp pm_view(assigns) do
    ~H"""
    <div style="max-width: 900px; margin: 0 auto;">
      <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
        <div class="section-label">PM Dashboard</div>
        <div class="display-heading"><%= greeting() %>, <%= first_name(@current_user.name) %></div>
        <div style="font-family: var(--font-mono); font-size: 12px; color: var(--chalk); opacity: 0.5; margin-top: 8px; text-transform: uppercase; letter-spacing: 1px;">
          <%= Date.utc_today() |> Calendar.strftime("%B %d, %Y") %> · <%= @today_total %> Reports Today
        </div>
      </div>

      <div class="stats-row" style="margin-bottom: 32px;">
        <div class="stat-card">
          <div class="stat-num"><%= @today_total %></div>
          <div class="stat-label">Total Today</div>
        </div>
        <div class="stat-card">
          <div class="stat-num" style="color: var(--orange);"><%= Map.get(@today_counts, :processing, 0) + Map.get(@today_counts, :pending, 0) %></div>
          <div class="stat-label">Processing</div>
        </div>
        <div class="stat-card">
          <div class="stat-num" style="color: var(--yellow);"><%= Map.get(@today_counts, :draft, 0) %></div>
          <div class="stat-label">Ready for Review</div>
        </div>
        <div class="stat-card">
          <div class="stat-num" style="color: var(--green);"><%= Map.get(@today_counts, :submitted, 0) %></div>
          <div class="stat-label">Submitted</div>
        </div>
      </div>

      <div style="display: flex; gap: 16px; flex-wrap: wrap;">
        <a href={~p"/logs"} class="btn-primary">View All Logs →</a>
        <a href={~p"/projects"} class="btn-ghost">Manage Projects</a>
      </div>
    </div>
    """
  end

  defp status_pill(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending -> %>
        <span class="pill pill-pending">Pending</span>
      <% :processing -> %>
        <span class="pill pill-active">Processing</span>
      <% :draft -> %>
        <span class="pill pill-pending">Ready for Review</span>
      <% :submitted -> %>
        <span class="pill pill-done">Submitted</span>
      <% :failed -> %>
        <span class="pill pill-failed">Failed</span>
      <% _ -> %>
        <span class="pill pill-pending"><%= @status %></span>
    <% end %>
    """
  end

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good Morning"
      hour < 17 -> "Good Afternoon"
      true -> "Good Evening"
    end
  end

  defp first_name(name) do
    name |> String.split(" ") |> List.first()
  end

  defp log_link(log) do
    case log.status do
      s when s in [:processing, :pending] -> ~p"/logs/#{log.id}/processing"
      _ -> ~p"/logs/#{log.id}"
    end
  end
end
