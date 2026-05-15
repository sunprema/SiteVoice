defmodule SitevoiceWeb.Logs.ProcessingLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @pipeline_steps ~w(transcribed structured pdf_generated)

  @impl true
  def mount(%{"id" => log_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    case Ash.get(Sitevoice.Reporting.DailyLog, log_id,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, log} ->
        report_ready = log.status in [:draft, :submitted]

        unless report_ready do
          topic = "org:#{org_id}:log:#{log_id}"
          Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
        end

        step_statuses =
          @pipeline_steps
          |> Enum.reduce(%{}, fn step, acc -> Map.put(acc, step, :waiting) end)

        {:ok,
         socket
         |> assign(:tenant, org_id)
         |> assign(:log, log)
         |> assign(:log_id, log_id)
         |> assign(:report_ready, report_ready)
         |> assign(:step_statuses, step_statuses)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Log not found.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_info({:pipeline_update, %{step: step, status: :complete}}, socket) do
    step_statuses = Map.put(socket.assigns.step_statuses, step, :done)
    {:noreply, assign(socket, :step_statuses, step_statuses)}
  end

  def handle_info({:report_ready, _payload}, socket) do
    {:noreply, assign(socket, :report_ready, true)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <body class="app-ui">
      <.nav current_user={@current_user} current_path="/logs" />
      <div class="app-page blueprint-bg" style="padding: 40px;">
        <div style="max-width: 560px; margin: 0 auto; text-align: center;">
          <div style="animation: fadeUp 0.6s ease both;">
            <div class="section-label" style="justify-content: center; margin-bottom: 8px;">Pipeline</div>
            <div class="display-heading" style="margin-bottom: 8px;">Processing</div>
            <div style="font-family: var(--font-mono); font-size: 12px; color: var(--chalk); opacity: 0.5; margin-bottom: 40px; letter-spacing: 1px;">
              <%= Date.utc_today() |> Calendar.strftime("%B %d, %Y") %>
            </div>
          </div>

          <%!-- Orb Animation --%>
          <div style="margin: 0 auto 48px; animation: fadeUp 0.6s 0.2s ease both;">
            <div class="orb-container">
              <div class="orb-ring ring1"></div>
              <div class="orb-ring ring2"></div>
              <div class="orb-ring ring3"></div>
              <div class="orb-center">
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2">
                  <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
                  <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
                </svg>
              </div>
            </div>
          </div>

          <%!-- Step List --%>
          <div style="display: flex; flex-direction: column; gap: 10px; text-align: left; margin-bottom: 32px; animation: fadeUp 0.6s 0.3s ease both;">
            <.proc_step
              title="Audio Uploaded"
              status={:done}
              icon="upload"
            />
            <.proc_step
              title="Transcription (Whisper AI)"
              status={step_status(@step_statuses, "transcribed")}
              icon="wave"
            />
            <.proc_step
              title="AI Structuring (Claude)"
              status={step_status(@step_statuses, "structured")}
              icon="table"
            />
            <.proc_step
              title="Photo Captioning"
              status={step_status(@step_statuses, "photos")}
              icon="photo"
            />
            <.proc_step
              title="PDF Generation"
              status={step_status(@step_statuses, "pdf_generated")}
              icon="file"
            />
          </div>

          <%!-- Report Ready Banner --%>
          <%= if @report_ready do %>
            <div class="ready-banner" style="animation: fadeUp 0.4s ease both;">
              <div>
                <div class="ready-banner-text">Report Ready</div>
                <div style="font-size: 13px; color: var(--chalk); opacity: 0.7; margin-top: 4px;">
                  Your daily log has been structured and is ready for review.
                </div>
              </div>
              <a href={~p"/logs/#{@log_id}"} class="btn-primary" style="white-space: nowrap;">
                View Report →
              </a>
            </div>
          <% end %>
        </div>
      </div>
    </body>
    """
  end

  defp proc_step(assigns) do
    ~H"""
    <div class={"proc-step #{@status}"}>
      <div class="proc-step-icon">
        <%= step_svg(@icon) %>
      </div>
      <div class="proc-step-title"><%= @title %></div>
      <div class="proc-step-badge">
        <%= case @status do %>
          <% :done -> %>✓
          <% :active -> %>●●●
          <% _ -> %>—
        <% end %>
      </div>
    </div>
    """
  end

  defp step_svg("upload") do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
      <polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
    </svg>
    """
  end

  defp step_svg("wave") do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/>
    </svg>
    """
  end

  defp step_svg("table") do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 21V9"/>
    </svg>
    """
  end

  defp step_svg("photo") do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/>
      <polyline points="21 15 16 10 5 21"/>
    </svg>
    """
  end

  defp step_svg("file") do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
      <polyline points="14 2 14 8 20 8"/>
    </svg>
    """
  end

  defp step_svg(_) do
    assigns = %{}

    ~H"""
    <svg width="16" height="16" viewBox="0 0 24 24"></svg>
    """
  end

  defp step_status(statuses, step) do
    Map.get(statuses, step, :waiting)
  end
end
