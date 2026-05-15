defmodule SitevoiceWeb.Logs.NewLive do
  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    project_result =
      Ash.get(Sitevoice.Projects.Project, project_id,
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

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("submit", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    project = socket.assigns.project

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

          case Ash.create(Sitevoice.Reporting.DailyLog, log_params,
                 action: :submit_recording,
                 tenant: org_id,
                 actor: user,
                 authorize?: true
               ) do
            {:ok, log} ->
              consume_photos(socket, org_id, project.id, log.id)
              {:noreply, push_navigate(socket, to: ~p"/logs/#{log.id}/processing")}

            {:error, error} ->
              {:noreply, assign(socket, :error, format_error(error))}
          end

        {:error, reason} ->
          {:noreply, assign(socket, :error, "Upload failed: #{inspect(reason)}")}
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

  defp consume_photos(socket, org_id, project_id, log_id) do
    consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
      key = "#{org_id}/photos/#{project_id}/#{log_id}/#{Ash.UUID.generate()}-#{entry.client_name}"

      case File.read(path) do
        {:ok, binary} ->
          Sitevoice.Storage.store_photo(key, binary)
          {:ok, key}

        {:error, _} ->
          {:ok, nil}
      end
    end)
  end

  @impl true
  def render(assigns) do
    audio_entries = assigns.uploads.audio.entries
    has_audio = audio_entries != []

    assigns =
      assigns
      |> assign(:has_audio, has_audio)
      |> assign(:audio_entries, audio_entries)
      |> assign(:photo_entries, assigns.uploads.photos.entries)

    ~H"""
    <body class="app-ui">
      <.nav current_user={@current_user} current_path="/projects" />
      <div class="app-page" style="padding: 40px; max-width: 700px; margin: 0 auto;">
        <div style="margin-bottom: 32px; animation: fadeUp 0.6s ease both;">
          <a href={~p"/projects/#{@project.id}"} class="chevron-link" style="margin-bottom: 16px; display: inline-flex;">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
            <%= @project.name %>
          </a>
          <div class="section-label" style="margin-top: 12px;">Submit Recording</div>
          <div class="display-heading">New Daily Log</div>
        </div>

        <%= if @error do %>
          <div class="alert-error" style="margin-bottom: 24px;"><%= @error %></div>
        <% end %>

        <form phx-submit="submit" phx-change="validate">
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

          <%!-- Photos Upload --%>
          <div class="card" style="margin-bottom: 32px;">
            <div class="section-label">Site Photos <span style="font-size: 10px; opacity: 0.5; font-family: var(--font-mono);">(optional, up to 10)</span></div>
            <div class="photo-strip" style="margin-bottom: 12px;">
              <%= for entry <- @photo_entries do %>
                <div class="photo-slot filled">
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
            disabled={not @has_audio}
            style={"width: 100%; justify-content: center; #{if not @has_audio, do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 2L11 13"/><path d="M22 2L15 22 11 13 2 9l20-7z"/></svg>
            Submit Recording
          </button>
        </form>
      </div>
    </body>
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
