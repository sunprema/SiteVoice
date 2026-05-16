defmodule SitevoiceWeb.WeeklyReportsLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  require Logger

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    with {:ok, project} <-
           Sitevoice.Projects.get_project(project_id,
             tenant: org_id,
             actor: user,
             authorize?: true
           ),
         {:ok, reports} <-
           Sitevoice.Reporting.list_weekly_reports_for_project(project_id,
             tenant: org_id,
             actor: user,
             authorize?: true,
             load: [:pdf_url]
           ) do
      {week_start, _week_end} = current_week()
      generating_report = find_generating_report(reports, week_start)

      if generating_report do
        topic = "org:#{org_id}:weekly_report:#{generating_report.id}"
        Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
      end

      {:ok,
       socket
       |> assign(:tenant, org_id)
       |> assign(:project, project)
       |> assign(:reports, reports)
       |> assign(:current_week_start, week_start)
       |> assign(:generating?, not is_nil(generating_report))
       |> assign(:toast, nil)}
    else
      {:error, reason} ->
        Logger.error("WeeklyReportsLive mount failed", project_id: project_id, reason: inspect(reason))
        {:ok, push_navigate(socket, to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("generate_report", _params, socket) do
    %{tenant: org_id, current_week_start: week_start, project: project, reports: reports} =
      socket.assigns

    if report_exists_for_week?(reports, week_start) do
      {:noreply, put_toast(socket, :info, "A report for this week already exists.")}
    else
      {_ws, week_end} = current_week()

      attrs = %{
        project_id: project.id,
        organization_id: org_id,
        week_start: week_start,
        week_end: week_end
      }

      case Sitevoice.Reporting.WeeklyReport
           |> Ash.Changeset.for_create(:create, attrs, authorize?: false, tenant: org_id)
           |> Ash.create() do
        {:ok, report} ->
          %{"report_id" => report.id, "organization_id" => org_id}
          |> Sitevoice.Workers.WeeklyReportWorker.new()
          |> Oban.insert()

          Phoenix.PubSub.subscribe(
            Sitevoice.PubSub,
            "org:#{org_id}:weekly_report:#{report.id}"
          )

          {:ok, report_with_url} =
            Ash.load(report, [:pdf_url], authorize?: false, tenant: org_id)

          updated_reports = [report_with_url | reports]

          {:noreply,
           socket
           |> assign(:reports, updated_reports)
           |> assign(:generating?, true)
           |> put_toast(:info, "Generating weekly report… This may take 30–60 seconds.")}

        {:error, reason} ->
          Logger.error("WeeklyReportsLive failed to create report",
            project_id: project.id,
            reason: inspect(reason)
          )
          {:noreply, put_toast(socket, :error, "Failed to start report generation.")}
      end
    end
  end

  @impl true
  def handle_info({:weekly_report_status, %{report_id: report_id, status: status}}, socket) do
    org_id = socket.assigns.tenant

    updated_reports =
      Enum.map(socket.assigns.reports, fn report ->
        if report.id == report_id do
          {:ok, reloaded} =
            Ash.get(Sitevoice.Reporting.WeeklyReport, report_id,
              authorize?: false,
              tenant: org_id,
              load: [:pdf_url]
            )

          reloaded
        else
          report
        end
      end)

    generating? = Enum.any?(updated_reports, &(&1.status in [:pending, :generating]))

    toast =
      case status do
        :ready -> {:ok, "Weekly report is ready! PDF available for download."}
        :failed -> {:error, "Report generation failed. You can try again."}
        _ -> nil
      end

    socket =
      socket
      |> assign(:reports, updated_reports)
      |> assign(:generating?, generating?)

    socket =
      case toast do
        {:ok, msg} -> put_toast(socket, :ok, msg)
        {:error, msg} -> put_toast(socket, :error, msg)
        nil -> socket
      end

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_path="/projects" />
      <div class="app-page blueprint-bg orange-glow" style="padding: 40px;">
        <div style="max-width: 1100px; margin: 0 auto;">

          <%!-- Breadcrumb --%>
          <div style="margin-bottom: 24px; font-size: 13px; color: var(--chalk); opacity: 0.6;">
            <a href={~p"/projects/#{@project.id}"} style="color: inherit; text-decoration: none;">
              <%= @project.name %>
            </a>
            <span style="margin: 0 8px;">›</span>
            <span>Weekly Reports</span>
          </div>

          <%!-- Header --%>
          <div style="display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
            <div>
              <div class="section-label">Weekly Reports</div>
              <div class="display-heading"><%= @project.name %></div>
            </div>

            <button
              phx-click="generate_report"
              disabled={@generating? or report_exists_for_week?(@reports, @current_week_start)}
              class="btn btn-primary"
              style="margin-top: 8px;"
            >
              <%= if @generating? do %>
                <span style="opacity: 0.7;">Generating…</span>
              <% else %>
                Generate This Week's Report
              <% end %>
            </button>
          </div>

          <%!-- Toast --%>
          <%= if @toast do %>
            <div class={"card " <> toast_class(@toast)} style="margin-bottom: 24px; padding: 14px 20px; font-size: 13px;">
              <%= elem(@toast, 1) %>
            </div>
          <% end %>

          <%!-- Reports Table --%>
          <div class="card" style="padding: 0; overflow: hidden;">
            <table class="data-table">
              <thead>
                <tr>
                  <th>Week</th>
                  <th>Status</th>
                  <th>Days Logged</th>
                  <th>Total Hours</th>
                  <th style="text-align: right;">Action</th>
                </tr>
              </thead>
              <tbody>
                <%= if @reports == [] do %>
                  <tr>
                    <td colspan="5" style="text-align: center; padding: 40px; color: var(--chalk); opacity: 0.5;">
                      No weekly reports yet. Generate one above.
                    </td>
                  </tr>
                <% else %>
                  <%= for report <- @reports do %>
                    <tr>
                      <td>
                        <span style="font-weight: 600;">
                          <%= format_date(report.week_start) %> – <%= format_date(report.week_end) %>
                        </span>
                      </td>
                      <td><.report_status_pill status={report.status} /></td>
                      <td style="color: var(--chalk); opacity: 0.8;">
                        <%= report.daily_log_count || "—" %>
                      </td>
                      <td style="color: var(--chalk); opacity: 0.8;">
                        <%= format_hours(report.total_labor_hours) %>
                      </td>
                      <td style="text-align: right;">
                        <%= if report.status == :ready and report.pdf_url do %>
                          <a
                            href={report.pdf_url}
                            target="_blank"
                            class="btn btn-secondary"
                            style="font-size: 12px; padding: 6px 14px;"
                          >
                            Download PDF
                          </a>
                        <% else %>
                          <span style="color: var(--chalk); opacity: 0.3; font-size: 12px;">—</span>
                        <% end %>
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

  defp report_status_pill(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending    -> %><span class="pill pill-pending">Pending</span>
      <% :generating -> %><span class="pill pill-active">Generating</span>
      <% :ready      -> %><span class="pill pill-done">Ready</span>
      <% :failed     -> %><span class="pill pill-failed">Failed</span>
      <% _           -> %><span class="pill pill-pending"><%= @status %></span>
    <% end %>
    """
  end

  defp report_exists_for_week?(reports, week_start) do
    Enum.any?(reports, fn r ->
      r.week_start == week_start and r.status in [:pending, :generating, :ready]
    end)
  end

  defp find_generating_report(reports, week_start) do
    Enum.find(reports, fn r ->
      r.week_start == week_start and r.status in [:pending, :generating]
    end)
  end

  defp current_week do
    today = Date.utc_today()
    dow = Date.day_of_week(today)
    week_start = Date.add(today, 1 - dow)
    week_end = Date.add(week_start, 6)
    {week_start, week_end}
  end

  defp format_date(%Date{} = d) do
    month =
      ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
      |> Enum.at(d.month - 1)

    "#{month} #{d.day}"
  end

  defp format_hours(nil), do: "—"
  defp format_hours(h) when h <= 0, do: "—"
  defp format_hours(h), do: "#{:erlang.float_to_binary(h * 1.0, decimals: 1)}h"

  defp put_toast(socket, type, msg) do
    assign(socket, :toast, {type, msg})
  end

  defp toast_class({:ok, _}), do: "toast-success"
  defp toast_class({:info, _}), do: ""
  defp toast_class({:error, _}), do: "toast-error"
  defp toast_class(_), do: ""
end
