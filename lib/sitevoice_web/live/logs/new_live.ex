defmodule SitevoiceWeb.Logs.NewLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  require Logger

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    project_result =
      Sitevoice.Projects.get_project(project_id,
        tenant: org_id,
        actor: user,
        authorize?: true
      )

    case project_result do
      {:ok, project} ->
        socket =
          socket
          |> assign(:tenant, org_id)
          |> assign(:project, project)
          |> assign(:error, nil)
          |> assign(:mode, :audio)
          |> assign(:typed_report, "")
          |> allow_upload(:audio,
            accept: ~w(.m4a .mp3 .wav .ogg),
            max_entries: 1,
            max_file_size: 50_000_000
          )
          |> allow_upload(:photos,
            accept: ~w(.jpg .jpeg .png .heic),
            max_entries: 10,
            max_file_size: 10_000_000
          )

        {:ok, socket}

      error ->
        Logger.error("Logs.NewLive mount failed for user=#{socket.assigns.current_user.id} project_id=#{project_id}: #{inspect(error)}")

        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
  end

  def handle_event("validate", params, socket) do
    typed = Map.get(params, "report_text", socket.assigns.typed_report)
    {:noreply, assign(socket, :typed_report, typed)}
  end

  def handle_event("submit", params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

    case socket.assigns.mode do
      :audio -> submit_audio(socket, params, user, org_id, project)
      :text -> submit_text(socket, params, user, org_id, project)
    end
  end

  defp submit_audio(socket, _params, user, org_id, project) do
    audio_entries = socket.assigns.uploads.audio.entries

    if audio_entries == [] do
      {:noreply, assign(socket, :error, "Please select an audio file.")}
    else
      case consume_audio(socket, org_id, project.id) do
        {:ok, audio_key} ->
          log_params = %{
            date: Date.utc_today(),
            audio_key: audio_key,
            project_id: project.id
          }

          case Sitevoice.Reporting.submit_recording(log_params,
                 tenant: org_id,
                 actor: user,
                 authorize?: true
               ) do
            {:ok, log} ->
              consume_photos(socket, user, org_id, project.id, log.id)
              {:noreply, push_navigate(socket, to: ~p"/logs/#{log.id}/processing")}

            {:error, error} ->
              {:noreply, assign(socket, :error, format_error(error))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Upload failed: #{inspect(reason)}")}
      end
    end
  end

  defp submit_text(socket, params, user, org_id, project) do
    text = String.trim(Map.get(params, "report_text", ""))

    if text == "" do
      {:noreply, assign(socket, :error, "Please enter a report.")}
    else
      log_params = %{
        date: Date.utc_today(),
        transcript: text,
        project_id: project.id
      }

      case Sitevoice.Reporting.submit_text_report(log_params,
             tenant: org_id,
             actor: user,
             authorize?: true
           ) do
        {:ok, log} ->
          consume_photos(socket, user, org_id, project.id, log.id)
          {:noreply, push_navigate(socket, to: ~p"/logs/#{log.id}/processing")}

        {:error, error} ->
          {:noreply, assign(socket, :error, format_error(error))}
      end
    end
  end

  defp consume_audio(socket, org_id, project_id) do
    audio_key_result =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        key = "#{org_id}/audio/#{project_id}/#{Ash.UUID.generate()}-#{entry.client_name}"

        case File.read(path) do
          {:ok, binary} ->
            case Sitevoice.Storage.store_audio(key, binary) do
              {:ok, _} -> {:ok, key}
              {:error, reason} -> {:postpone, reason}
            end

          {:error, reason} ->
            {:postpone, reason}
        end
      end)

    case audio_key_result do
      [key] -> {:ok, key}
      [] -> {:error, "No audio file consumed"}
    end
  end

  defp consume_photos(socket, user, org_id, project_id, log_id) do
    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      key = "#{org_id}/photos/#{project_id}/#{log_id}/#{Ash.UUID.generate()}-#{entry.client_name}"

      with {:ok, binary} <- File.read(path),
           {:ok, _} <- Sitevoice.Storage.store_photo(key, binary),
           {:ok, _} <-
             Sitevoice.Reporting.upload_photo(key, log_id,
               tenant: org_id,
               actor: user,
               authorize?: true
             ) do
        {:ok, key}
      else
        {:error, reason} ->
          Logger.error("Photo upload failed for #{entry.client_name}: #{inspect(reason)}")
          {:ok, nil}
      end
    end)
  end

  @impl true
  def render(assigns) do
    audio_entries = assigns.uploads.audio.entries
    has_audio = audio_entries != []
    has_text = String.trim(assigns.typed_report) != ""
    can_submit = (assigns.mode == :audio and has_audio) or (assigns.mode == :text and has_text)

    assigns =
      assigns
      |> assign(:has_audio, has_audio)
      |> assign(:audio_entries, audio_entries)
      |> assign(:photo_entries, assigns.uploads.photos.entries)
      |> assign(:can_submit, can_submit)

    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/projects" />
      <div class="app-page blueprint-bg orange-glow">
        <div style="max-width: 700px; margin: 0 auto; padding: 40px 24px;">
        <div style="margin-bottom: 32px;">
          <a href={~p"/projects/#{@project.id}"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
            <%= @project.name %>
          </a>
          <div class="section-label" style="margin-top: 12px;">New Daily Log</div>
          <div class="display-heading" style="font-size: 26px;">Submit Report</div>
        </div>

        <%!-- Mode toggle --%>
        <div style="display: flex; gap: 0; margin-bottom: 28px; border: 1px solid var(--wire); border-radius: 8px; overflow: hidden;">
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="audio"
            style={"flex: 1; padding: 12px; font-family: var(--font-mono); font-size: 12px; letter-spacing: 1px; text-transform: uppercase; border: none; cursor: pointer; transition: all 0.2s; #{if @mode == :audio, do: "background: var(--orange); color: var(--ink);", else: "background: transparent; color: var(--chalk); opacity: 0.6;"}"}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display: inline; vertical-align: middle; margin-right: 6px;"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
            Audio Recording
          </button>
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="text"
            style={"flex: 1; padding: 12px; font-family: var(--font-mono); font-size: 12px; letter-spacing: 1px; text-transform: uppercase; border: none; border-left: 1px solid var(--wire); cursor: pointer; transition: all 0.2s; #{if @mode == :text, do: "background: var(--orange); color: var(--ink);", else: "background: transparent; color: var(--chalk); opacity: 0.6;"}"}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display: inline; vertical-align: middle; margin-right: 6px;"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            Type Report
          </button>
        </div>

        <%= if @error do %>
          <div class="alert-error" style="margin-bottom: 24px;"><%= @error %></div>
        <% end %>

        <form phx-submit="submit" phx-change="validate">
          <%= if @mode == :audio do %>
            <%!-- Audio Upload --%>
            <div class="card" style="margin-bottom: 24px;">
              <div class="section-label">Audio Recording</div>
              <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-bottom: 16px;">
                Upload your site walkthrough recording (.m4a, .mp3, .wav, .ogg — max 50MB)
              </div>
              <.live_file_input upload={@uploads.audio} style="display:none" id="audio-input" />
              <label for={@uploads.audio.ref} class="upload-zone" style="display: block; cursor: pointer;">
                <%= if @audio_entries == [] do %>
                  <div style="color: var(--chalk); opacity: 0.5;">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin: 0 auto 8px; display: block;"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                    <div style="font-family: var(--font-mono); font-size: 12px; letter-spacing: 1px; text-transform: uppercase;">Click to select audio file</div>
                  </div>
                <% else %>
                  <%= for entry <- @audio_entries do %>
                    <div style="display: flex; align-items: center; gap: 12px;">
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--orange)" stroke-width="2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                      <div>
                        <div style="font-size: 13px; color: var(--white);"><%= entry.client_name %></div>
                        <div style="font-family: var(--font-mono); font-size: 11px; color: var(--chalk); opacity: 0.5;"><%= trunc(entry.client_size / 1024) %> KB</div>
                      </div>
                    </div>
                    <div style="margin-top: 10px; background: var(--wire); border-radius: 4px; height: 4px; overflow: hidden;">
                      <div style={"background: var(--orange); width: #{entry.progress}%; height: 100%; transition: width 0.3s;"}></div>
                    </div>
                  <% end %>
                <% end %>
              </label>
              <%= for err <- upload_errors(@uploads.audio) do %>
                <div class="alert-error" style="margin-top: 8px; font-size: 12px;"><%= friendly_error(err) %></div>
              <% end %>
            </div>
          <% else %>
            <%!-- Text Report --%>
            <div class="card" style="margin-bottom: 24px;">
              <div class="section-label">Report Text</div>
              <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-bottom: 16px;">
                Type your daily site report below. Claude will structure it into the standard log format.
              </div>
              <textarea
                name="report_text"
                placeholder="Describe today's work: labor on site, progress made, equipment used, materials delivered, any delays or safety notes..."
                style="width: 100%; min-height: 200px; background: var(--ink); border: 1px solid var(--wire); border-radius: 6px; color: var(--chalk); font-size: 14px; line-height: 1.6; padding: 14px; resize: vertical; font-family: var(--font-sans); box-sizing: border-box; outline: none;"
                phx-debounce="300"
              ><%= @typed_report %></textarea>
            </div>
          <% end %>

          <%!-- Photos Upload --%>
          <div class="card" style="margin-bottom: 32px;">
            <div class="section-label">Site Photos <span style="font-size: 10px; opacity: 0.5; font-family: var(--font-mono);">(optional, up to 10)</span></div>
            <div class="photo-strip" style="margin-bottom: 12px;">
              <%= for entry <- @photo_entries do %>
                <div class="photo-slot filled" style="overflow: hidden;">
                  <.live_img_preview entry={entry} style="width: 100%; height: 100%; object-fit: cover;" />
                  <div style="position: absolute; bottom: 2px; right: 4px; font-family: var(--font-mono); font-size: 9px; color: var(--orange);">
                    <%= trunc(entry.progress) %>%
                  </div>
                </div>
              <% end %>
              <label for={@uploads.photos.ref} class="photo-slot" style="cursor: pointer;">
                <span>+</span>
              </label>
            </div>
            <.live_file_input upload={@uploads.photos} style="display:none" />
            <%= for err <- upload_errors(@uploads.photos) do %>
              <div class="alert-error" style="margin-top: 8px; font-size: 12px;"><%= friendly_error(err) %></div>
            <% end %>
          </div>

          <button
            type="submit"
            class="btn-primary"
            disabled={not @can_submit}
            style={"width: 100%; justify-content: center; #{if not @can_submit, do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 2L11 13"/><path d="M22 2L15 22 11 13 2 9l20-7z"/></svg>
            <%= if @mode == :audio, do: "Submit Recording", else: "Submit Report" %>
          </button>
        </form>
        </div>
      </div>
    </div>
    """
  end

  defp friendly_error(:too_large), do: "File is too large."
  defp friendly_error(:not_accepted), do: "File type not accepted."
  defp friendly_error(:too_many_files), do: "Too many files."
  defp friendly_error(err), do: inspect(err)

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors |> Enum.map(&Exception.message/1) |> Enum.join(", ")
  end

  defp format_error(error), do: inspect(error)
end
