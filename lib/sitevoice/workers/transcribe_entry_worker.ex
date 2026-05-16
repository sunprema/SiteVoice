defmodule Sitevoice.Workers.TranscribeEntryWorker do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @construction_prompt """
  Construction site daily log. Foreman reporting field observations.
  Common terms: rebar, BIM, HVAC, soffit, pour schedule, OSHA,
  subcontractor, footing, conduit, sheathing, curtain wall,
  means and methods, RFI, submittal, punchlist, change order.
  """

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        attempt: attempt,
        args: %{"entry_id" => entry_id, "organization_id" => org_id}
      }) do
    Logger.metadata(entry_id: entry_id, org_id: org_id, oban_job_id: job_id, attempt: attempt)
    Logger.info("TranscribeEntryWorker starting")

    with {:ok, entry} <- fetch_entry(entry_id, org_id),
         {:ok, language} <- fetch_language(entry, org_id),
         {:ok, audio_binary} <- Sitevoice.Storage.fetch(entry.audio_key),
         {:ok, transcript} <- transcribe(audio_binary, language) do
      apply_transcript(entry, transcript, org_id)
      broadcast_transcribed(entry, transcript, org_id)
      Logger.info("TranscribeEntryWorker completed", entry_id: entry_id)
      :ok
    else
      {:error, reason} ->
        Logger.error("TranscribeEntryWorker failed: #{inspect(reason)}")
        mark_failed(entry_id, org_id)
        {:error, reason}
    end
  end

  defp fetch_entry(entry_id, org_id) do
    Ash.get(Sitevoice.Reporting.LogEntry, entry_id, authorize?: false, tenant: org_id)
  end

  defp fetch_language(entry, org_id) do
    case Ash.get(Sitevoice.Reporting.DailyLog, entry.daily_log_id,
           authorize?: false,
           tenant: org_id,
           load: [:foreman]
         ) do
      {:ok, log} -> {:ok, log.foreman.preferred_language}
      error -> error
    end
  end

  defp transcribe(audio_binary, preferred_language) do
    language = if preferred_language == :es, do: "es", else: "en"
    audio_bytes = byte_size(audio_binary)

    Logger.info("TranscribeEntryWorker calling Whisper — #{audio_bytes} bytes, lang=#{language}")

    case Application.fetch_env(:sitevoice, :openai_api_key) do
      {:ok, key} when is_binary(key) and key != "" ->
        do_transcribe(audio_binary, language, key)

      _ ->
        {:error, "OpenAI API key not configured"}
    end
  end

  defp do_transcribe(audio_binary, language, api_key) do
    Req.post(
      "https://api.openai.com/v1/audio/transcriptions",
      [
        headers: [{"Authorization", "Bearer #{api_key}"}],
        form_multipart: [
          file: {audio_binary, filename: "recording.m4a", content_type: "audio/m4a"},
          model: "whisper-1",
          language: language,
          prompt: @construction_prompt,
          response_format: "json"
        ],
        receive_timeout: 60_000
      ] ++ Application.get_env(:sitevoice, :openai_req_options, [])
    )
    |> case do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        Logger.info("TranscribeEntryWorker Whisper succeeded — #{String.length(text)} chars")
        {:ok, text}

      {:ok, %{status: s, body: b}} ->
        body_preview = b |> inspect() |> String.slice(0, 300)
        Logger.error("TranscribeEntryWorker Whisper error — status=#{s} body=#{body_preview}")
        {:error, "Whisper HTTP #{s}: #{body_preview}"}

      {:error, %{reason: reason}} ->
        Logger.error("TranscribeEntryWorker Whisper connection error — #{inspect(reason)}")
        {:error, "Whisper connection error: #{inspect(reason)}"}

      {:error, r} ->
        Logger.error("TranscribeEntryWorker Whisper failed — #{inspect(r)}")
        {:error, r}
    end
  end

  defp apply_transcript(entry, transcript, org_id) do
    Ash.update!(entry, %{transcript: transcript},
      action: :apply_transcript,
      authorize?: false,
      tenant: org_id
    )
  end

  defp broadcast_transcribed(entry, transcript, org_id) do
    topic = "org:#{org_id}:log:#{entry.daily_log_id}"

    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      topic,
      {:entry_transcribed, %{entry_id: entry.id, transcript: transcript}}
    )
  end

  defp mark_failed(entry_id, org_id) do
    case Ash.get(Sitevoice.Reporting.LogEntry, entry_id, authorize?: false, tenant: org_id) do
      {:ok, entry} ->
        Ash.update!(entry, %{},
          action: :mark_transcription_failed,
          authorize?: false,
          tenant: org_id
        )

      {:error, err} ->
        Logger.error("TranscribeEntryWorker could not mark entry failed: #{inspect(err)}")
    end
  end
end
