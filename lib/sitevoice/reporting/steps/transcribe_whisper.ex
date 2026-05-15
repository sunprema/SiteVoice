defmodule Sitevoice.Steps.TranscribeWhisper do
  use Reactor.Step

  require Logger

  @construction_prompt """
  Construction site daily log. Foreman reporting end-of-shift.
  Common terms: rebar, BIM, HVAC, soffit, pour schedule, OSHA,
  subcontractor, footing, conduit, sheathing, curtain wall,
  means and methods, RFI, submittal, punchlist, change order.
  """

  def run(%{audio: audio_binary, language: lang}, _, _) do
    language = if lang == :es, do: "es", else: "en"
    audio_bytes = byte_size(audio_binary)

    with :ok <- check_api_key(:openai) do
      do_run(audio_binary, audio_bytes, language)
    end
  end

  defp do_run(audio_binary, audio_bytes, language) do
    Logger.info("Whisper transcription starting — #{audio_bytes} bytes, lang=#{language}")

    :telemetry.span(
      [:sitevoice, :whisper, :transcribe],
      %{language: language, audio_bytes: audio_bytes},
      fn ->
        result =
          Req.post(
            "https://api.openai.com/v1/audio/transcriptions",
            [
              headers: [{"Authorization", "Bearer #{api_key()}"}],
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
              Logger.info("Whisper transcription succeeded — #{String.length(text)} chars")
              {:ok, text}

            {:ok, %{status: s, body: b}} ->
              body_preview = b |> inspect() |> String.slice(0, 300)
              Logger.error("Whisper API error — status=#{s} body=#{body_preview}")
              {:error, "Whisper HTTP #{s}: #{body_preview}"}

            {:error, %{reason: reason}} ->
              Logger.error("Whisper request failed — #{inspect(reason)}")
              {:error, "Whisper connection error: #{inspect(reason)}"}

            {:error, r} ->
              Logger.error("Whisper request failed — #{inspect(r)}")
              {:error, r}
          end

        {result, %{}}
      end
    )
  end

  def compensate(_, _, _, _), do: :ok

  defp check_api_key(:openai) do
    case Application.fetch_env(:sitevoice, :openai_api_key) do
      {:ok, key} when is_binary(key) and key != "" ->
        :ok

      _ ->
        Logger.error("Whisper step cannot run — :openai_api_key not configured (set OPENAI_API_KEY)")
        {:error, "OpenAI API key not configured"}
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :openai_api_key)
end
