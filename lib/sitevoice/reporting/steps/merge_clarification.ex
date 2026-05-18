defmodule Sitevoice.Steps.MergeClarification do
  @moduledoc """
  Given the original transcript, the previously extracted fields, and the
  clarification addendum transcript, ask Claude to produce a single updated
  set of structured fields. The result replaces the extracted fields wholesale —
  Claude is responsible for reconciliation.
  """

  use Reactor.Step

  require Logger

  @model "claude-sonnet-4-20250514"
  @max_tokens 2000
  @receive_timeout 30_000

  @system_prompt """
  You are an expert construction daily log assistant. You will be given the
  PROJECT CONTEXT, the original TRANSCRIPT, the already-EXTRACTED fields, and
  a CLARIFICATION transcript from the foreman answering follow-up questions.

  Reconcile everything and return ONLY valid JSON with these keys:
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

  def run(%{log: log, organization_id: org_id}, _, _) do
    with :ok <- check_api_key(),
         {:ok, project} <- load_project(log, org_id) do
      do_run(log, project)
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp load_project(log, org_id) do
    Ash.get(Sitevoice.Projects.Project, log.project_id,
      tenant: org_id,
      authorize?: false
    )
  end

  defp do_run(log, project) do
    user_message = build_user_message(log, project)

    Logger.info("MergeClarification calling Claude",
      log_id: log.id,
      transcript_chars: String.length(log.transcript || ""),
      clarification_chars: String.length(log.clarification_transcript || "")
    )

    Req.post(
      "https://api.anthropic.com/v1/messages",
      [
        headers: [
          {"x-api-key", api_key()},
          {"anthropic-version", "2023-06-01"},
          {"content-type", "application/json"}
        ],
        json: %{
          model: @model,
          max_tokens: @max_tokens,
          system: @system_prompt,
          messages: [%{role: "user", content: user_message}]
        },
        receive_timeout: @receive_timeout
      ] ++ Application.get_env(:sitevoice, :anthropic_req_options, [])
    )
    |> parse_response()
  end

  defp build_user_message(log, project) do
    extracted = %{
      labor: log.labor,
      progress: log.progress,
      equipment: log.equipment,
      materials: log.materials,
      delays: log.delays,
      safety: log.safety,
      accuracy_score: log.accuracy_score
    }

    """
    PROJECT CONTEXT:
    #{project.daily_log_context}

    REQUIRED SECTIONS: #{Enum.join(project.required_sections, ", ")}

    ORIGINAL TRANSCRIPT:
    #{log.transcript || ""}

    EXTRACTED FIELDS (may have gaps):
    #{Jason.encode!(extracted)}

    CLARIFICATION (foreman's follow-up answers):
    #{log.clarification_transcript || ""}
    """
  end

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    case Jason.decode(t) do
      {:ok, data} ->
        structured = Map.new(data, fn {k, v} -> {String.to_atom(k), v} end)

        Logger.info("MergeClarification succeeded",
          accuracy_score: structured[:accuracy_score],
          labor_entries: length(List.wrap(structured[:labor]))
        )

        {:ok, structured}

      {:error, decode_err} ->
        Logger.error("MergeClarification invalid JSON: #{inspect(decode_err)}")
        {:error, "Invalid JSON from Claude: #{inspect(decode_err)}"}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}) do
    Logger.error("MergeClarification Claude HTTP #{s}: #{inspect(b) |> String.slice(0, 200)}")
    {:error, "Claude HTTP #{s}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("MergeClarification request failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp check_api_key do
    case Application.fetch_env(:sitevoice, :anthropic_api_key) do
      {:ok, key} when is_binary(key) and key != "" -> :ok
      _ -> {:error, "Anthropic API key not configured"}
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
