defmodule SitevoiceWeb.Logs.ClarificationLive do
  @moduledoc """
  Shown to the foreman when the AI pipeline detects gaps in their daily log
  and wants a short voice addendum. The foreman can either record a follow-up
  or skip straight to draft review.
  """

  use SitevoiceWeb, :live_view

  import SitevoiceWeb.NavComponent

  on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}

  require Logger

  @impl true
  def mount(%{"id" => log_id}, _session, socket) do
    user = socket.assigns.current_user
    org_id = to_string(user.organization_id)

    case Sitevoice.Reporting.get_log(log_id, tenant: org_id, actor: user, authorize?: true) do
      {:ok, log} when log.foreman_id == user.id ->
        cond do
          log.status == :awaiting_clarification ->
            socket =
              socket
              |> assign(:tenant, org_id)
              |> assign(:log, log)
              |> assign(:log_id, log_id)
              |> assign(:questions, log.clarification_questions || [])
              |> assign(:error, nil)
              |> assign(:submitting?, false)
              |> allow_upload(:clarification_audio,
                accept: ~w(.m4a .mp3 .wav .ogg),
                max_entries: 1,
                max_file_size: 50_000_000
              )

            {:ok, socket}

          log.status in [:draft, :submitted] ->
            {:ok, push_navigate(socket, to: ~p"/logs/#{log_id}")}

          true ->
            {:ok, push_navigate(socket, to: ~p"/logs/#{log_id}/processing")}
        end

      {:ok, _other_log} ->
        {:ok,
         socket
         |> put_flash(:error, "You are not authorized to view this clarification screen.")
         |> push_navigate(to: ~p"/dashboard")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Log not found.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("skip", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    log = socket.assigns.log

    case Ash.update(log, %{},
           action: :skip_clarification,
           tenant: org_id,
           actor: user,
           authorize?: true
         ) do
      {:ok, _log} ->
        {:noreply, push_navigate(socket, to: ~p"/logs/#{log.id}/processing")}

      {:error, error} ->
        Logger.error("ClarificationLive skip failed: #{inspect(error)}")
        {:noreply, assign(socket, :error, "Could not skip — please try again.")}
    end
  end

  def handle_event("submit", _params, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.tenant
    log = socket.assigns.log

    audio_entries = socket.assigns.uploads.clarification_audio.entries

    if audio_entries == [] do
      {:noreply, assign(socket, :error, "Please record or upload an audio answer.")}
    else
      socket = assign(socket, :submitting?, true)

      case consume_clarification_audio(socket, org_id, log.id) do
        {:ok, audio_key, duration} ->
          case Ash.update(log, %{clarification_audio_key: audio_key, clarification_audio_duration: duration},
                 action: :submit_clarification,
                 tenant: org_id,
                 actor: user,
                 authorize?: true
               ) do
            {:ok, _log} ->
              {:noreply, push_navigate(socket, to: ~p"/logs/#{log.id}/processing")}

            {:error, error} ->
              Logger.error("ClarificationLive submit failed: #{inspect(error)}")

              {:noreply,
               socket
               |> assign(:submitting?, false)
               |> assign(:error, "Could not submit answer — please try again.")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:submitting?, false)
           |> assign(:error, "Upload failed: #{inspect(reason)}")}
      end
    end
  end

  defp consume_clarification_audio(socket, org_id, log_id) do
    results =
      consume_uploaded_entries(socket, :clarification_audio, fn %{path: path}, entry ->
        key = "#{org_id}/audio/clarifications/#{log_id}/#{Ash.UUID.generate()}-#{entry.client_name}"

        case File.read(path) do
          {:ok, binary} ->
            case Sitevoice.Storage.store_audio(key, binary) do
              {:ok, _} ->
                duration = trunc(entry.client_size / 16_000)
                {:ok, {key, duration}}

              {:error, reason} ->
                {:postpone, reason}
            end

          {:error, reason} ->
            {:postpone, reason}
        end
      end)

    case results do
      [{key, duration}] -> {:ok, key, duration}
      [] -> {:error, "No audio file consumed"}
    end
  end

  @impl true
  def render(assigns) do
    audio_entries = assigns.uploads.clarification_audio.entries
    has_audio = audio_entries != []

    assigns =
      assigns
      |> assign(:audio_entries, audio_entries)
      |> assign(:has_audio, has_audio)

    ~H"""
    <div class="app-ui">
      <.nav current_user={@current_user} current_organization={@current_organization} current_path="/logs" />
      <div class="app-page blueprint-bg orange-glow">
        <div style="max-width: 640px; margin: 0 auto; padding: 40px 24px;">
          <div style="margin-bottom: 28px;">
            <div class="section-label">Quick Follow-Up</div>
            <div class="display-heading" style="font-size: 26px;">A Few Questions</div>
            <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-top: 8px;">
              We noticed a few gaps in your report. Answer these in one short voice clip and we'll
              fold them in — or skip and edit during review.
            </div>
          </div>

          <%= if @error do %>
            <div class="alert-error" style="margin-bottom: 24px;"><%= @error %></div>
          <% end %>

          <div class="card" style="margin-bottom: 24px;">
            <div class="section-label">Questions</div>
            <ol style="margin: 12px 0 0; padding-left: 22px; color: var(--chalk); line-height: 1.7;">
              <%= for q <- @questions do %>
                <li style="margin-bottom: 8px;"><%= question_text(q) %></li>
              <% end %>
            </ol>
          </div>

          <form phx-submit="submit" phx-change="validate">
            <div class="card" style="margin-bottom: 24px;">
              <div class="section-label">Your Answer (audio)</div>
              <div style="font-size: 13px; color: var(--chalk); opacity: 0.6; margin-bottom: 16px;">
                Upload a short clip answering all questions (.m4a, .mp3, .wav, .ogg — max 50MB)
              </div>
              <.live_file_input upload={@uploads.clarification_audio} style="display:none" id="clarification-audio-input" />
              <label for={@uploads.clarification_audio.ref} class="upload-zone" style="display: block; cursor: pointer;">
                <%= if @audio_entries == [] do %>
                  <div style="color: var(--chalk); opacity: 0.5;">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="margin: 0 auto 8px; display: block;"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>
                    <div style="font-family: var(--font-mono); font-size: 12px; letter-spacing: 1px; text-transform: uppercase;">Click to select audio</div>
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
              <%= for err <- upload_errors(@uploads.clarification_audio) do %>
                <div class="alert-error" style="margin-top: 8px; font-size: 12px;"><%= friendly_error(err) %></div>
              <% end %>
            </div>

            <div style="display: flex; gap: 12px;">
              <button
                type="submit"
                class="btn-primary"
                disabled={not @has_audio or @submitting?}
                style={"flex: 1; justify-content: center; #{if not @has_audio or @submitting?, do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
              >
                <%= if @submitting?, do: "Submitting…", else: "Submit Answer" %>
              </button>
              <button
                type="button"
                phx-click="skip"
                class="btn-ghost"
                disabled={@submitting?}
                style={"flex: 1; justify-content: center; #{if @submitting?, do: "opacity: 0.4; cursor: not-allowed;", else: ""}"}
              >
                Skip — Edit During Review
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp question_text(%{"question" => q}), do: q
  defp question_text(%{question: q}), do: q
  defp question_text(_), do: ""

  defp friendly_error(:too_large), do: "File is too large."
  defp friendly_error(:not_accepted), do: "File type not accepted."
  defp friendly_error(:too_many_files), do: "Too many files."
  defp friendly_error(err), do: inspect(err)
end
