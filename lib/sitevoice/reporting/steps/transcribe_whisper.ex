defmodule Sitevoice.Steps.TranscribeWhisper do
  use Reactor.Step

  @construction_prompt """
  Construction site daily log. Foreman reporting end-of-shift.
  Common terms: rebar, BIM, HVAC, soffit, pour schedule, OSHA,
  subcontractor, footing, conduit, sheathing, curtain wall,
  means and methods, RFI, submittal, punchlist, change order.
  """

  def run(%{audio: audio_binary, language: lang}, _, _) do
    language = if lang == :es, do: "es", else: "en"

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
      {:ok, %{status: 200, body: %{"text" => text}}} -> {:ok, text}
      {:ok, %{status: s, body: b}} -> {:error, "Whisper #{s}: #{inspect(b)}"}
      {:error, r} -> {:error, r}
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp api_key, do: Application.fetch_env!(:sitevoice, :openai_api_key)
end
