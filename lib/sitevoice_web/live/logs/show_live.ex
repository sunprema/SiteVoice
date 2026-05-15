defmodule SitevoiceWeb.Logs.ShowLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @categories [
    {:labor,     "Labor",     "#60A5FA"},
    {:progress,  "Progress",  "#34D399"},
    {:equipment, "Equipment", "#F59E0B"},
    {:materials, "Materials", "#A78BFA"},
    {:delays,    "Delays",    "#F87171"},
    {:safety,    "Safety",    "#22C55E"}
  ]

  @impl true
  def mount(%{"id" => log_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    case Sitevoice.Reporting.get_log(log_id,
           tenant: org_id,
           actor: user,
           authorize?: true,
           load: [:pdf_url, :audio_url, :photos, :foreman, :project]
         ) do
      {:ok, log} ->
        {:ok,
         socket
         |> assign(:tenant, org_id)
         |> assign(:log, log)
         |> assign(:show_success, false)
         |> assign(:approve_error, nil)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Log not found.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("approve_submit", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    log = socket.assigns.log

    case Sitevoice.Reporting.approve_and_submit(log, %{},
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, updated_log} ->
        {:noreply,
         socket
         |> assign(:log, updated_log)
         |> assign(:show_success, true)
         |> assign(:approve_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :approve_error, format_error(error))}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :all_complete, all_categories_present?(assigns.log))
    assigns = assign(assigns, :categories, @categories)

    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_path="/logs" />
      <div class="app-page" style="padding: 40px; max-width: 860px; margin: 0 auto;">

        <%!-- Header --%>
        <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
          <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px; margin-bottom: 8px;">
            <div>
              <a href={~p"/dashboard"} class="chevron-link" style="margin-bottom: 12px; display: inline-flex;">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
                Dashboard
              </a>
              <div class="display-heading" style="margin-top: 8px;"><%= Calendar.strftime(@log.date, "%B %d, %Y") %></div>
            </div>
            <div style="display: flex; align-items: center; gap: 12px; flex-wrap: wrap;">
              <.log_status_pill status={@log.status} />
              <%= if @log.pdf_url do %>
                <a href={@log.pdf_url} target="_blank" class="btn-secondary">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                  Download PDF
                </a>
              <% end %>
              <%= if can_approve?(@current_user, @log) do %>
                <button class="btn-primary" phx-click="approve_submit">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
                  Approve &amp; Submit
                </button>
              <% end %>
            </div>
          </div>
          <div style="font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5; text-transform: uppercase; letter-spacing: 1px;">
            <%= @log.project && @log.project.name %> · <%= @log.foreman && @log.foreman.name %>
          </div>
        </div>

        <%= if @approve_error do %>
          <div class="alert-error" style="margin-bottom: 20px;"><%= @approve_error %></div>
        <% end %>

        <%!-- Success Overlay --%>
        <%= if @show_success do %>
          <div class="success-card" style="margin-bottom: 32px; animation: fadeUp 0.4s ease both;">
            <div class="success-title">REPORT SENT</div>
            <div style="font-size: 14px; color: var(--chalk); opacity: 0.7; margin-bottom: 24px;">
              Your daily log has been submitted successfully.
            </div>
            <div style="text-align: left; max-width: 360px; margin: 0 auto;">
              <div class="delivery-row">
                <span class="delivery-check">✓</span>
                <span>PDF emailed to Project Manager</span>
              </div>
              <div class="delivery-row">
                <span class="delivery-check">✓</span>
                <span>Sent to Procore integration queue</span>
              </div>
              <div class="delivery-row">
                <span class="delivery-check">✓</span>
                <span>Archived to cloud storage</span>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- AI Completeness Banner --%>
        <%= if @all_complete do %>
          <div class="alert-success" style="margin-bottom: 24px;">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
            AI confidence: All 6 categories captured. Report is complete.
          </div>
        <% end %>

        <%!-- Transcript --%>
        <%= if @log.transcript do %>
          <div class="card" style="margin-bottom: 24px;">
            <div class="section-label">Transcript</div>
            <div style="font-size: 13px; line-height: 1.7; color: var(--chalk); opacity: 0.8; font-style: italic;">
              "<%= @log.transcript %>"
            </div>
          </div>
        <% end %>

        <%!-- Category Cards --%>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px; margin-bottom: 32px;">
          <%= for {field, label, color} <- @categories do %>
            <.category_card
              field={field}
              label={label}
              color={color}
              entries={Map.get(@log, field) || []}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp category_card(assigns) do
    ~H"""
    <div class="log-category">
      <div class="log-category-header">
        <div class="category-dot" style={"background: #{@color};"}></div>
        <div class="category-name"><%= @label %></div>
        <div class="category-count"><%= length(@entries) %> items</div>
      </div>
      <div class="log-category-body">
        <%= if @entries == [] do %>
          <div style="font-size: 12px; color: var(--chalk); opacity: 0.4; font-style: italic;">No entries captured.</div>
        <% else %>
          <%= for entry <- @entries do %>
            <div class="log-entry">
              <span style={"color: #{@color}; flex-shrink: 0;"}>›</span>
              <span><%= entry_text(entry) %></span>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp log_status_pill(assigns) do
    ~H"""
    <%= case @status do %>
      <% :pending -> %><span class="pill pill-pending">Pending</span>
      <% :processing -> %><span class="pill pill-active">Processing</span>
      <% :draft -> %><span class="pill pill-pending">Ready for Review</span>
      <% :submitted -> %><span class="pill pill-done">Submitted</span>
      <% :failed -> %><span class="pill pill-failed">Failed</span>
      <% _ -> %><span class="pill pill-pending"><%= @status %></span>
    <% end %>
    """
  end

  # labor: {crew, headcount, trade, hours, subcontractor}
  defp entry_text(%{"trade" => trade, "headcount" => headcount, "hours" => hours} = entry) do
    crew = Map.get(entry, "crew")
    sub = Map.get(entry, "subcontractor")

    [
      "#{headcount} #{trade}",
      crew && "(#{crew})",
      "#{hours} hrs",
      sub && "via #{sub}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # materials: {item, quantity, received_at, note}
  defp entry_text(%{"item" => item, "quantity" => qty} = entry) do
    note = Map.get(entry, "note")
    received = Map.get(entry, "received_at")

    [item, "qty: #{qty}", received && "received #{received}", note]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # equipment: {item, status, note}
  defp entry_text(%{"item" => item, "status" => status} = entry) do
    note = Map.get(entry, "note")
    if note, do: "#{item} — #{status} (#{note})", else: "#{item} — #{status}"
  end

  # safety: {description, incident_type}
  defp entry_text(%{"description" => desc, "incident_type" => type}) do
    "#{type}: #{desc}"
  end

  # delays: {description, cause, impact, hours_lost}
  defp entry_text(%{"description" => desc, "cause" => cause} = entry) do
    hours_lost = Map.get(entry, "hours_lost")
    impact = Map.get(entry, "impact")

    [desc, "cause: #{cause}", hours_lost && "#{hours_lost} hrs lost", impact]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # progress: {description, location, percentage_complete}
  defp entry_text(%{"description" => desc} = entry) do
    loc = Map.get(entry, "location")
    pct = Map.get(entry, "percentage_complete")

    [desc, loc, pct && "#{pct}% complete"]
    |> Enum.filter(& &1)
    |> Enum.join(" — ")
  end

  defp entry_text(entry) when is_map(entry) do
    Map.get(entry, "note") || Map.get(entry, "text") || inspect(entry)
  end

  defp entry_text(entry) when is_binary(entry), do: entry
  defp entry_text(entry), do: inspect(entry)

  defp all_categories_present?(log) do
    [:labor, :progress, :equipment, :materials, :delays, :safety]
    |> Enum.all?(fn field -> Map.get(log, field, []) != [] end)
  end

  defp can_approve?(user, log) do
    log.status == :draft &&
      (user.role == :org_admin || (log.foreman_id && log.foreman_id == user.id))
  end

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(%Ash.Error.Forbidden{}) do
    "You are not authorized to perform this action."
  end

  defp format_error(error), do: inspect(error)
end
