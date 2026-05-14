defmodule Sitevoice.Steps.StructureWithClaude do
  use Reactor.Step

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
  end

  def compensate(_, _, _, _), do: :ok

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    case Jason.decode(t) do
      {:ok, data} -> {:ok, Map.new(data, fn {k, v} -> {String.to_atom(k), v} end)}
      {:error, _} -> {:error, "Invalid JSON from Claude: #{t}"}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}), do: {:error, "Claude #{s}: #{inspect(b)}"}
  defp parse_response({:error, r}), do: {:error, r}

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
