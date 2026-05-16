defmodule SitevoiceWeb.Logs.LogSessionLive do
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
         {:ok, log_or_nil} <- find_today_log(user, org_id, project_id) do
      socket =
        socket
        |> assign(:tenant, org_id)
        |> assign(:project, project)
        |> assign(:error, nil)
        |> assign(:add_mode, :voice)
        |> assign(:note_text, "")
        |> assign(:submitting, false)
        |> allow_upload(:voice_memo,
          accept: ~w(.m4a .mp3 .wav .ogg),
          max_entries: 1,
          max_file_size: 50_000_000
        )
        |> allow_upload(:photos,
          accept: ~w(.jpg .jpeg .png .heic .webp),
          max_entries: 10,
          max_file_size: 10_000_000
        )

      socket =
        case log_or_nil do
          nil ->
            socket
            |> assign(:log, nil)
            |> assign(:entries, [])
            |> assign(:attendance_rows, [])
            |> assign(:page_state, :no_log)

          log when log.status in [:processing, :draft, :submitted] ->
            redirect_for_status(socket, log)

          log ->
            entries = load_entries(log.id, org_id)
            attendance_rows = load_attendance(log.id, org_id)
            Phoenix.PubSub.subscribe(Sitevoice.PubSub, "org:#{org_id}:log:#{log.id}")

            socket
            |> assign(:log, log)
            |> assign(:entries, entries)
            |> assign(:attendance_rows, attendance_rows)
            |> assign(:page_state, :session)
        end

      {:ok, socket}
    else
      error ->
        Logger.error("LogSessionLive mount failed for user=#{socket.assigns.current_user.id} project_id=#{project_id}: #{inspect(error)}")

        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  # --- Start Log ---

  @impl true
  def handle_event("start_log", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    case Sitevoice.Reporting.start_log(
           %{date: Date.utc_today(), project_id: project.id},
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, log} ->
        Phoenix.PubSub.subscribe(Sitevoice.PubSub, "org:#{org_id}:log:#{log.id}")
        attendance_rows = load_attendance(log.id, org_id)

        {:noreply,
         socket
         |> assign(:log, log)
         |> assign(:entries, [])
         |> assign(:attendance_rows, attendance_rows)
         |> assign(:page_state, :session)}

      {:error, error} ->
        {:noreply, assign(socket, :error, format_error(error))}
    end
  end

  # --- Add mode toggle ---

  def handle_event("set_add_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :add_mode, String.to_existing_atom(mode))}
  end

  # --- Add voice memo ---

  def handle_event("add_voice_memo", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project
    log = socket.assigns.log

    audio_entries = socket.assigns.uploads.voice_memo.entries

    if audio_entries == [] do
      {:noreply, assign(socket, :error, "Please select an audio file.")}
    else
      case consume_audio_upload(socket, org_id, project.id, log.id) do
        {:ok, {audio_key, duration}} ->
          params = %{
            audio_key: audio_key,
            audio_duration: duration,
            captured_at: DateTime.utc_now(),
            sort_order: length(socket.assigns.entries),
            daily_log_id: log.id
          }

          case Sitevoice.Reporting.add_voice_memo(params,
                 tenant: org_id,
                 actor: user,
                 authorize?: true
               ) do
            {:ok, entry} ->
              entries = socket.assigns.entries ++ [entry]
              {:noreply, socket |> assign(:entries, entries) |> assign(:error, nil)}

            {:error, error} ->
              {:noreply, assign(socket, :error, format_error(error))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Upload failed: #{inspect(reason)}")}
      end
    end
  end

  # --- Add text note ---

  def handle_event("add_text_note", %{"note_text" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, assign(socket, :error, "Please enter a note.")}
    else
      user = socket.assigns.current_user
      org_id = socket.assigns.tenant
      log = socket.assigns.log

      params = %{
        text: text,
        captured_at: DateTime.utc_now(),
        sort_order: length(socket.assigns.entries),
        daily_log_id: log.id
      }

      case Sitevoice.Reporting.add_text_note(params,
             tenant: org_id,
             actor: user,
             authorize?: true
           ) do
        {:ok, entry} ->
          entries = socket.assigns.entries ++ [entry]
          {:noreply, socket |> assign(:entries, entries) |> assign(:note_text, "") |> assign(:error, nil)}

        {:error, error} ->
          {:noreply, assign(socket, :error, format_error(error))}
      end
    end
  end

  # --- Add photos ---

  def handle_event("add_photos", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project
    log = socket.assigns.log

    photo_entries = socket.assigns.uploads.photos.entries

    if photo_entries == [] do
      {:noreply, assign(socket, :error, "Please select at least one photo.")}
    else
      results =
        consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
          key =
            "#{org_id}/photos/#{project.id}/#{log.id}/#{Ash.UUID.generate()}-#{entry.client_name}"

          with {:ok, binary} <- File.read(path),
               {:ok, _} <- Sitevoice.Storage.store_photo(key, binary) do
            params = %{
              photo_key: key,
              captured_at: DateTime.utc_now(),
              sort_order: length(socket.assigns.entries),
              daily_log_id: log.id
            }

            case Sitevoice.Reporting.add_photo_entry(params,
                   tenant: org_id,
                   actor: user,
                   authorize?: true
                 ) do
              {:ok, log_entry} ->
                {:ok, {:ok, log_entry}}

              {:error, reason} ->
                Logger.error("add_photo_entry failed for #{entry.client_name}: #{inspect(reason)}")
                {:ok, {:error, "Failed to save photo: #{format_error(reason)}"}}
            end
          else
            {:error, reason} ->
              Logger.error("Photo storage failed for #{entry.client_name}: #{inspect(reason)}")
              {:ok, {:error, "Failed to upload photo: #{inspect(reason)}"}}
          end
        end)

      errors = for {:error, msg} <- results, do: msg
      new_entries = for {:ok, entry} <- results, do: entry
      entries = socket.assigns.entries ++ new_entries

      socket =
        if errors == [] do
          assign(socket, :error, nil)
        else
          assign(socket, :error, Enum.join(errors, "; "))
        end

      {:noreply, assign(socket, :entries, entries)}
    end
  end

  # --- Remove entry ---

  def handle_event("remove_entry", %{"entry_id" => entry_id}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant

    case Ash.get(Sitevoice.Reporting.LogEntry, entry_id, authorize?: false, tenant: org_id) do
      {:ok, entry} ->
        case Ash.destroy(entry,
               action: :remove_entry,
               tenant: org_id,
               actor: user,
               authorize?: true
             ) do
          :ok ->
            entries = Enum.reject(socket.assigns.entries, &(&1.id == entry_id))
            {:noreply, assign(socket, :entries, entries)}

          {:error, error} ->
            {:noreply, assign(socket, :error, format_error(error))}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # --- Update attendance row ---

  def handle_event("update_attendance", %{"row_id" => row_id} = params, socket) do
    org_id = socket.assigns.tenant
    user = socket.assigns.current_user

    present = parse_int(params["present"], 0)
    absent = parse_int(params["absent"], 0)
    hours = parse_float(params["hours"], 8.0)

    case Ash.get(Sitevoice.Reporting.DailyAttendance, row_id,
           authorize?: false,
           tenant: org_id
         ) do
      {:ok, row} ->
        case Ash.update(row, %{headcount_present: present, headcount_absent: absent, hours: hours},
               action: :update_attendance,
               tenant: org_id,
               actor: user,
               authorize?: true
             ) do
          {:ok, updated} ->
            rows =
              Enum.map(socket.assigns.attendance_rows, fn r ->
                if r.id == updated.id, do: %{updated | crew_template: r.crew_template}, else: r
              end)

            {:noreply, socket |> assign(:attendance_rows, rows) |> assign(:error, nil)}

          {:error, error} ->
            {:noreply, assign(socket, :error, format_error(error))}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # --- Validate (form changes) ---

  def handle_event("validate", %{"note_text" => text}, socket) do
    {:noreply, assign(socket, :note_text, text)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  # --- Generate report ---

  def handle_event("generate_report", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    log = socket.assigns.log

    case Ash.update(log, %{},
           action: :submit_entries,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, updated_log} ->
        {:noreply, push_navigate(socket, to: ~p"/logs/#{updated_log.id}/processing")}

      {:error, error} ->
        {:noreply, assign(socket, :error, format_error(error))}
    end
  end

  # --- PubSub: real-time transcription updates ---

  @impl true
  def handle_info({:entry_transcribed, %{entry_id: entry_id, transcript: transcript}}, socket) do
    entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == entry_id do
          %{entry | status: :transcribed, transcript: transcript}
        else
          entry
        end
      end)

    {:noreply, assign(socket, :entries, entries)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # --- Render ---

  @impl true
  def render(assigns) do
    has_transcribed =
      Enum.any?(assigns.entries || [], &(&1.status == :transcribed))

    assigns = assign(assigns, :can_generate, has_transcribed)

    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/projects" />
      <div class="app-page blueprint-bg orange-glow" style="padding: 40px;">
        <div style="max-width: 760px; margin: 0 auto;">

          <%!-- Header --%>
          <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
            <a href={~p"/projects/#{@project.id}"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
              <%= @project.name %>
            </a>
            <div class="section-label" style="margin-top: 12px;">Daily Log Session</div>
            <div class="display-heading"><%= Calendar.strftime(Date.utc_today(), "%B %d, %Y") %></div>
          </div>

          <%= if @error do %>
            <div class="alert-error" style="margin-bottom: 24px;"><%= @error %></div>
          <% end %>

          <%= if @page_state == :no_log do %>
            <%!-- Start log CTA --%>
            <div class="card" style="text-align: center; padding: 60px 40px; animation: fadeUp 0.6s 0.1s ease both;">
              <div style="width: 64px; height: 64px; background: rgba(255,107,53,0.1); border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px;">
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="var(--orange)" stroke-width="1.5"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><line x1="9" y1="15" x2="15" y2="15"/></svg>
              </div>
              <div style="font-size: 18px; font-weight: 600; color: var(--white); margin-bottom: 8px;">No log started today</div>
              <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-bottom: 32px; line-height: 1.6;">
                Start a session to add voice memos, notes, and photos throughout your shift.<br/>Generate the report whenever you're ready.
              </div>
              <button class="btn-primary" phx-click="start_log" style="margin: 0 auto;">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                Start Today's Log
              </button>
            </div>

          <% else %>
            <%!-- Session active --%>
            <div style="display: grid; grid-template-columns: 1fr 340px; gap: 24px; align-items: start;">

              <%!-- Attendance panel --%>
              <%= if @attendance_rows != [] do %>
                <div class="card" style="margin-bottom: 24px;">
                  <div class="section-label" style="margin-bottom: 16px;">Crew Attendance</div>
                  <div style="overflow-x: auto;">
                    <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
                      <thead>
                        <tr style="border-bottom: 1px solid var(--wire);">
                          <th style="text-align: left; font-family: var(--font-mono); font-size: 10px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; padding: 0 12px 10px 0; font-weight: normal;">Crew</th>
                          <th style="text-align: left; font-family: var(--font-mono); font-size: 10px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; padding: 0 12px 10px 0; font-weight: normal;">Trade</th>
                          <th style="text-align: center; font-family: var(--font-mono); font-size: 10px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; padding: 0 8px 10px; font-weight: normal;">Present</th>
                          <th style="text-align: center; font-family: var(--font-mono); font-size: 10px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; padding: 0 8px 10px; font-weight: normal;">Absent</th>
                          <th style="text-align: center; font-family: var(--font-mono); font-size: 10px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; padding: 0 8px 10px; font-weight: normal;">Hours</th>
                          <th style="width: 60px;"></th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for row <- @attendance_rows do %>
                          <tr style="border-bottom: 1px solid rgba(255,255,255,0.04);">
                            <td style="padding: 10px 12px 10px 0; color: var(--chalk);">
                              <%= row.crew_template.name %>
                              <%= if row.crew_template.subcontractor do %>
                                <div style="font-size: 11px; opacity: 0.45; font-family: var(--font-mono);"><%= row.crew_template.subcontractor %></div>
                              <% end %>
                            </td>
                            <td style="padding: 10px 12px 10px 0;">
                              <span style="font-family: var(--font-mono); font-size: 11px; color: var(--orange); letter-spacing: 0.5px; text-transform: uppercase;"><%= row.crew_template.trade %></span>
                            </td>
                            <td style="padding: 10px 8px; text-align: center;">
                              <input
                                type="number"
                                min="0"
                                value={row.headcount_present}
                                id={"present-#{row.id}"}
                                style="width: 52px; background: var(--ink); border: 1px solid var(--wire); border-radius: 4px; color: var(--chalk); text-align: center; padding: 4px; font-size: 13px; outline: none;"
                                phx-blur="update_attendance"
                                phx-value-row_id={row.id}
                                phx-value-absent={row.headcount_absent}
                                phx-value-hours={row.hours}
                                name="present"
                              />
                            </td>
                            <td style="padding: 10px 8px; text-align: center;">
                              <input
                                type="number"
                                min="0"
                                value={row.headcount_absent}
                                id={"absent-#{row.id}"}
                                style="width: 52px; background: var(--ink); border: 1px solid var(--wire); border-radius: 4px; color: var(--chalk); text-align: center; padding: 4px; font-size: 13px; outline: none;"
                                phx-blur="update_attendance"
                                phx-value-row_id={row.id}
                                phx-value-present={row.headcount_present}
                                phx-value-hours={row.hours}
                                name="absent"
                              />
                            </td>
                            <td style="padding: 10px 8px; text-align: center;">
                              <input
                                type="number"
                                min="0"
                                step="0.5"
                                value={row.hours}
                                id={"hours-#{row.id}"}
                                style="width: 60px; background: var(--ink); border: 1px solid var(--wire); border-radius: 4px; color: var(--chalk); text-align: center; padding: 4px; font-size: 13px; outline: none;"
                                phx-blur="update_attendance"
                                phx-value-row_id={row.id}
                                phx-value-present={row.headcount_present}
                                phx-value-absent={row.headcount_absent}
                                name="hours"
                              />
                            </td>
                            <td style="padding: 10px 0 10px 8px; text-align: right;">
                              <span style="font-family: var(--font-mono); font-size: 10px; color: #4ade80; letter-spacing: 0.5px;">saved</span>
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              <% else %>
                <%= if @page_state == :session do %>
                  <div style="margin-bottom: 20px; padding: 12px 16px; border: 1px dashed rgba(255,255,255,0.1); border-radius: 6px; font-size: 12px; color: var(--chalk); opacity: 0.45; font-family: var(--font-mono);">
                    No crew templates set up for this project.
                    <a href={~p"/projects/#{@project.id}"} style="color: var(--orange); text-decoration: none; margin-left: 4px;">Set up crews →</a>
                  </div>
                <% end %>
              <% end %>

              <%!-- Entry timeline --%>
              <div>
                <div class="section-label" style="margin-bottom: 16px;">
                  Entries (<%= length(@entries) %>)
                </div>

                <%= if @entries == [] do %>
                  <div class="card" style="text-align: center; padding: 40px; color: var(--chalk); opacity: 0.5;">
                    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin: 0 auto 12px; display: block;"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                    <div style="font-family: var(--font-mono); font-size: 12px; letter-spacing: 1px; text-transform: uppercase;">Add your first entry →</div>
                  </div>
                <% else %>
                  <div style="display: flex; flex-direction: column; gap: 12px;">
                    <%= for entry <- @entries do %>
                      <div class="card" style="position: relative; padding: 16px 20px;">
                        <button
                          phx-click="remove_entry"
                          phx-value-entry_id={entry.id}
                          style="position: absolute; top: 12px; right: 12px; background: none; border: none; cursor: pointer; color: var(--chalk); opacity: 0.3; padding: 4px; line-height: 1;"
                          title="Remove entry"
                        >✕</button>

                        <%= case entry.type do %>
                          <% :voice_memo -> %>
                            <div style="display: flex; align-items: flex-start; gap: 12px;">
                              <div style="width: 32px; height: 32px; background: rgba(255,107,53,0.1); border-radius: 8px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; margin-top: 2px;">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--orange)" stroke-width="2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                              </div>
                              <div style="flex: 1; min-width: 0;">
                                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px;">
                                  <span style="font-family: var(--font-mono); font-size: 11px; letter-spacing: 1px; text-transform: uppercase; color: var(--orange);">Voice Memo</span>
                                  <%= render_entry_status(assigns, entry) %>
                                </div>
                                <%= if entry.transcript do %>
                                  <div style="font-size: 13px; color: var(--chalk); line-height: 1.6; opacity: 0.8;">
                                    <%= entry.transcript %>
                                  </div>
                                <% end %>
                                <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; margin-top: 6px;">
                                  <%= format_time(entry.captured_at) %>
                                  <%= if entry.audio_duration, do: " · #{entry.audio_duration}s", else: "" %>
                                </div>
                              </div>
                            </div>

                          <% :text_note -> %>
                            <div style="display: flex; align-items: flex-start; gap: 12px;">
                              <div style="width: 32px; height: 32px; background: rgba(255,255,255,0.05); border-radius: 8px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; margin-top: 2px;">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--chalk)" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                              </div>
                              <div style="flex: 1; min-width: 0;">
                                <div style="font-family: var(--font-mono); font-size: 11px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; margin-bottom: 6px;">Note</div>
                                <div style="font-size: 13px; color: var(--chalk); line-height: 1.6;">{entry.text}</div>
                                <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4; margin-top: 6px;">
                                  <%= format_time(entry.captured_at) %>
                                </div>
                              </div>
                            </div>

                          <% :photo -> %>
                            <div style="display: flex; align-items: center; gap: 12px;">
                              <div style="width: 56px; height: 56px; background: rgba(255,255,255,0.05); border-radius: 8px; overflow: hidden; flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--chalk)" stroke-width="1.5" style="opacity: 0.4;"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
                              </div>
                              <div>
                                <div style="font-family: var(--font-mono); font-size: 11px; letter-spacing: 1px; text-transform: uppercase; color: var(--chalk); opacity: 0.5; margin-bottom: 4px;">Photo</div>
                                <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.4;">
                                  <%= format_time(entry.captured_at) %> · Will be captioned on report generation
                                </div>
                              </div>
                            </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%!-- Generate Report button --%>
                <div style="margin-top: 28px;">
                  <button
                    class="btn-primary"
                    phx-click="generate_report"
                    disabled={not @can_generate}
                    style={"width: 100%; justify-content: center; #{if not @can_generate, do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
                  >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 2L11 13"/><path d="M22 2L15 22 11 13 2 9l20-7z"/></svg>
                    Generate Report
                  </button>
                  <%= if not @can_generate and @entries != [] do %>
                    <div style="text-align: center; font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.4; margin-top: 8px; letter-spacing: 1px; text-transform: uppercase;">
                      Waiting for transcription to complete…
                    </div>
                  <% end %>
                </div>
              </div>

              <%!-- Add panel --%>
              <div style="position: sticky; top: 24px;">
                <div class="card" style="animation: fadeUp 0.6s 0.15s ease both;">
                  <div class="section-label" style="margin-bottom: 16px;">Add Entry</div>

                  <%!-- Tab bar --%>
                  <div style="display: flex; gap: 0; margin-bottom: 20px; border: 1px solid var(--wire); border-radius: 6px; overflow: hidden;">
                    <%= for {mode, icon, label} <- [
                      {:voice, ~s(<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/>), "Voice"},
                      {:note, ~s(<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>), "Note"},
                      {:photo, ~s(<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>), "Photo"}
                    ] do %>
                      <button
                        type="button"
                        phx-click="set_add_mode"
                        phx-value-mode={mode}
                        style={"flex: 1; padding: 8px 4px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.5px; text-transform: uppercase; border: none; cursor: pointer; transition: all 0.2s; display: flex; flex-direction: column; align-items: center; gap: 4px; #{if @add_mode == mode, do: "background: var(--orange); color: var(--ink);", else: "background: transparent; color: var(--chalk); opacity: 0.55; border-right: 1px solid var(--wire);"}"}
                      >
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                          <%= {:safe, icon} %>
                        </svg>
                        <%= label %>
                      </button>
                    <% end %>
                  </div>

                  <%!-- Voice memo panel --%>
                  <%= if @add_mode == :voice do %>
                    <form phx-submit="add_voice_memo" phx-change="validate">
                      <.live_file_input upload={@uploads.voice_memo} style="display:none" id="voice-input" />
                      <label for={@uploads.voice_memo.ref} class="upload-zone" style="display: block; cursor: pointer; margin-bottom: 12px; min-height: 80px;">
                        <%= if @uploads.voice_memo.entries == [] do %>
                          <div style="color: var(--chalk); opacity: 0.5; text-align: center;">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin: 0 auto 6px; display: block;"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                            <div style="font-family: var(--font-mono); font-size: 11px; letter-spacing: 1px; text-transform: uppercase;">Select audio file</div>
                          </div>
                        <% else %>
                          <%= for entry <- @uploads.voice_memo.entries do %>
                            <div style="display: flex; align-items: center; gap: 10px;">
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--orange)" stroke-width="2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                              <div>
                                <div style="font-size: 12px; color: var(--white);"><%= entry.client_name %></div>
                                <div style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5;"><%= trunc(entry.client_size / 1024) %> KB</div>
                              </div>
                            </div>
                            <div style="margin-top: 8px; background: var(--wire); border-radius: 2px; height: 3px;">
                              <div style={"background: var(--orange); width: #{entry.progress}%; height: 100%; transition: width 0.3s;"}></div>
                            </div>
                          <% end %>
                        <% end %>
                      </label>
                      <%= for err <- upload_errors(@uploads.voice_memo) do %>
                        <div class="alert-error" style="margin-bottom: 8px; font-size: 11px;"><%= friendly_error(err) %></div>
                      <% end %>
                      <button
                        type="submit"
                        class="btn-primary"
                        disabled={@uploads.voice_memo.entries == []}
                        style={"width: 100%; justify-content: center; font-size: 13px; padding: 10px; #{if @uploads.voice_memo.entries == [], do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
                      >
                        Add Voice Memo
                      </button>
                    </form>
                  <% end %>

                  <%!-- Text note panel --%>
                  <%= if @add_mode == :note do %>
                    <form phx-submit="add_text_note" phx-change="validate">
                      <textarea
                        name="note_text"
                        placeholder="Enter your field note…"
                        style="width: 100%; min-height: 120px; background: var(--ink); border: 1px solid var(--wire); border-radius: 6px; color: var(--chalk); font-size: 13px; line-height: 1.6; padding: 12px; resize: vertical; font-family: var(--font-sans); box-sizing: border-box; outline: none; margin-bottom: 12px;"
                        phx-debounce="300"
                      ><%= @note_text %></textarea>
                      <button
                        type="submit"
                        class="btn-primary"
                        disabled={String.trim(@note_text) == ""}
                        style={"width: 100%; justify-content: center; font-size: 13px; padding: 10px; #{if String.trim(@note_text) == "", do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
                      >
                        Add Note
                      </button>
                    </form>
                  <% end %>

                  <%!-- Photo panel --%>
                  <%= if @add_mode == :photo do %>
                    <form phx-submit="add_photos" phx-change="validate">
                      <div class="photo-strip" style="margin-bottom: 12px;">
                        <%= for entry <- @uploads.photos.entries do %>
                          <div class="photo-slot filled" style="overflow: hidden;">
                            <.live_img_preview entry={entry} style="width: 100%; height: 100%; object-fit: cover;" />
                            <div style="position: absolute; bottom: 2px; right: 4px; font-family: var(--font-mono); font-size: 9px; color: var(--orange);"><%= trunc(entry.progress) %>%</div>
                          </div>
                        <% end %>
                        <label for={@uploads.photos.ref} class="photo-slot" style="cursor: pointer;"><span>+</span></label>
                      </div>
                      <.live_file_input upload={@uploads.photos} style="display:none" />
                      <%= for err <- upload_errors(@uploads.photos) do %>
                        <div class="alert-error" style="margin-bottom: 8px; font-size: 11px;"><%= friendly_error(err) %></div>
                      <% end %>
                      <button
                        type="submit"
                        class="btn-primary"
                        disabled={@uploads.photos.entries == []}
                        style={"width: 100%; justify-content: center; font-size: 13px; padding: 10px; #{if @uploads.photos.entries == [], do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
                      >
                        Add Photos
                      </button>
                    </form>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp find_today_log(user, org_id, project_id) do
    require Ash.Query
    today = Date.utc_today()

    query =
      Sitevoice.Reporting.DailyLog
      |> Ash.Query.for_read(:list_for_foreman, %{foreman_id: user.id})
      |> Ash.Query.filter(date == ^today and project_id == ^project_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: user, authorize?: true) do
      {:ok, [log | _]} -> {:ok, log}
      {:ok, []} -> {:ok, nil}
      {:error, _} = err -> err
    end
  end

  defp load_entries(log_id, org_id) do
    case Ash.read(Sitevoice.Reporting.LogEntry,
           action: :for_log,
           arguments: %{daily_log_id: log_id},
           authorize?: false,
           tenant: org_id
         ) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  defp redirect_for_status(socket, log) when log.status in [:draft, :submitted] do
    socket |> push_navigate(to: ~p"/logs/#{log.id}")
  end

  defp redirect_for_status(socket, log) do
    socket |> push_navigate(to: ~p"/logs/#{log.id}/processing")
  end

  defp consume_audio_upload(socket, org_id, project_id, log_id) do
    result =
      consume_uploaded_entries(socket, :voice_memo, fn %{path: path}, entry ->
        key =
          "#{org_id}/audio/#{project_id}/#{log_id}/#{Ash.UUID.generate()}-#{entry.client_name}"

        size_kb = div(entry.client_size, 1024)
        duration = estimate_duration(size_kb)

        case File.read(path) do
          {:ok, binary} ->
            case Sitevoice.Storage.store_audio(key, binary) do
              {:ok, _} -> {:ok, {key, duration}}
              {:error, reason} -> {:postpone, reason}
            end

          {:error, reason} ->
            {:postpone, reason}
        end
      end)

    case result do
      [{key, duration}] -> {:ok, {key, duration}}
      _ -> {:error, "No audio file consumed"}
    end
  end

  defp estimate_duration(size_kb) do
    # rough estimate: ~1KB per second for compressed audio
    max(1, div(size_kb, 16))
  end

  defp render_entry_status(assigns, entry) do
    assigns = assign(assigns, :entry, entry)

    ~H"""
    <%= case @entry.status do %>
      <% :pending -> %>
        <span style="font-family: var(--font-mono); font-size: 10px; color: var(--chalk); opacity: 0.5; letter-spacing: 0.5px; text-transform: uppercase;">
          Transcribing…
        </span>
      <% :transcribed -> %>
        <span style="font-family: var(--font-mono); font-size: 10px; color: #4ade80; letter-spacing: 0.5px; text-transform: uppercase;">
          ✓ Transcribed
        </span>
      <% :failed -> %>
        <span style="font-family: var(--font-mono); font-size: 10px; color: #f87171; letter-spacing: 0.5px; text-transform: uppercase;">
          ✕ Failed
        </span>
      <% _ -> %>
    <% end %>
    """
  end

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(_), do: ""

  defp friendly_error(:too_large), do: "File is too large."
  defp friendly_error(:not_accepted), do: "File type not accepted."
  defp friendly_error(:too_many_files), do: "Too many files."
  defp friendly_error(err), do: inspect(err)

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)

  defp load_attendance(log_id, org_id) do
    case Sitevoice.Reporting.list_attendances_for_log(log_id,
           tenant: org_id,
           authorize?: false
         ) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float(val, _default) when is_float(val), do: val

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default
end
