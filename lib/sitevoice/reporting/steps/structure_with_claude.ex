defmodule Sitevoice.Steps.StructureWithClaude do
  use Reactor.Step

  require Logger

  @system_prompt """
  You are an expert construction daily log assistant. Extract information
  from the transcript and return ONLY valid JSON with these keys:
  labor, progress, equipment, materials, delays, safety, accuracy_score.

  - labor:     [{crew, headcount, trade, hours, subcontractor}]
  - progress:  [{description, location, percentage_complete}]
  - equipment: [{item, status, note}]
  - materials: [{item, quantity, received_at, note}]
  - delays:    [{description, cause, impact, hours_lost}]
  - safety:    [{description, incident_type}]
  - accuracy_score: float 0.0–1.0

  Empty sections → []. Return ONLY JSON. No preamble. No fences.
  """

  def run(%{transcript: transcript}, _, _) do
    transcript_chars = String.length(transcript)
    Logger.info("Claude structuring starting", transcript_chars: transcript_chars)

    :telemetry.span(
      [:sitevoice, :claude, :structure],
      %{transcript_chars: transcript_chars},
      fn ->
        result =
          Req.post(
            "https://api.anthropic.com/v1/messages",
            [
              headers: [
                {"x-api-key", api_key()},
                {"anthropic-version", "2023-06-01"},
                {"content-type", "application/json"}
              ],
              json: %{
                model: "claude-sonnet-4-20250514",
                max_tokens: 2000,
                system: @system_prompt,
                messages: [%{role: "user", content: transcript}]
              },
              receive_timeout: 30_000
            ] ++ Application.get_env(:sitevoice, :anthropic_req_options, [])
          )
          |> parse_response()

        {result, %{}}
      end
    )
  end

  def compensate(_, _, _, _), do: :ok

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    case Jason.decode(t) do
      {:ok, data} ->
        structured = Map.new(data, fn {k, v} -> {String.to_atom(k), v} end)

        Logger.info("Claude structuring succeeded",
          accuracy_score: structured[:accuracy_score],
          labor_entries: length(List.wrap(structured[:labor])),
          delays_entries: length(List.wrap(structured[:delays])),
          safety_entries: length(List.wrap(structured[:safety]))
        )

        {:ok, structured}

      {:error, decode_err} ->
        Logger.error("Claude returned invalid JSON",
          raw_response: String.slice(t, 0, 500),
          decode_error: inspect(decode_err)
        )

        {:error, "Invalid JSON from Claude: #{t}"}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}) do
    Logger.error("Claude API returned error status", status: s, body: inspect(b))
    {:error, "Claude #{s}: #{inspect(b)}"}
  end

  defp parse_response({:error, r}) do
    Logger.error("Claude HTTP request failed", reason: inspect(r))
    {:error, r}
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
