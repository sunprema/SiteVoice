defmodule Sitevoice.Steps.StructureWithClaude do
  use Reactor.Step

  require Logger

  @base_system_prompt """
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

  def run(%{transcript: transcript} = args, _, _) do
    with :ok <- check_api_key() do
      do_run(transcript, args[:project])
    end
  end

  defp do_run(transcript, project) do
    transcript_chars = String.length(transcript)
    Logger.info("Claude structuring starting — #{transcript_chars} chars")

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
                system: build_system_prompt(project),
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

  defp build_system_prompt(nil), do: @base_system_prompt

  defp build_system_prompt(%{daily_log_context: context, required_sections: sections}) do
    """
    You are an expert construction daily log assistant working on this project:

    PROJECT CONTEXT:
    #{context}

    REQUIRED SECTIONS for this project: #{Enum.join(sections, ", ")}

    Extract information from the transcript and return ONLY valid JSON with these keys:
    labor, progress, equipment, materials, delays, safety, accuracy_score.

    - labor:     [{crew, headcount, trade, hours, subcontractor}]
    - progress:  [{description, location, percentage_complete}]
    - equipment: [{item, status, note}]
    - materials: [{item, quantity, received_at, note}]
    - delays:    [{description, cause, impact, hours_lost}]
    - safety:    [{description, incident_type}]
    - accuracy_score: float 0.0–1.0

    Lower accuracy_score when the transcript does not adequately cover the REQUIRED SECTIONS.
    Empty sections → []. Return ONLY JSON. No preamble. No fences.
    """
  end

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
        raw_preview = String.slice(t, 0, 500)
        Logger.error("Claude returned invalid JSON — #{inspect(decode_err)} raw=#{raw_preview}")
        {:error, "Invalid JSON from Claude: #{inspect(decode_err)}"}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}) do
    body_preview = b |> inspect() |> String.slice(0, 300)
    Logger.error("Claude API error — status=#{s} body=#{body_preview}")
    {:error, "Claude HTTP #{s}: #{body_preview}"}
  end

  defp parse_response({:error, %{reason: reason}}) do
    Logger.error("Claude request failed — #{inspect(reason)}")
    {:error, "Claude connection error: #{inspect(reason)}"}
  end

  defp parse_response({:error, r}) do
    Logger.error("Claude request failed — #{inspect(r)}")
    {:error, r}
  end

  defp check_api_key do
    case Application.fetch_env(:sitevoice, :anthropic_api_key) do
      {:ok, key} when is_binary(key) and key != "" ->
        :ok

      _ ->
        Logger.error("Claude step cannot run — :anthropic_api_key not configured (set ANTHROPIC_API_KEY)")
        {:error, "Anthropic API key not configured"}
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
