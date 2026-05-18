defmodule Sitevoice.Steps.GenerateClarifications do
  @moduledoc """
  Asks Claude for 1–3 short, project-aware questions to fill the missing pieces
  of an incomplete daily log. Falls back to deterministic templates when Claude
  is unavailable or returns an unparseable response.
  """

  use Reactor.Step

  require Logger

  @model "claude-sonnet-4-20250514"
  @max_tokens 600
  @receive_timeout 15_000

  def run(%{log: log, organization_id: org_id, missing: missing}, _, _) do
    with {:ok, project} <- load_project(log, org_id) do
      case do_run(log, project, missing) do
        {:ok, questions} ->
          {:ok, questions}

        {:error, _reason} ->
          Logger.warning("GenerateClarifications falling back to templates",
            log_id: log.id,
            missing: missing
          )

          {:ok, template_fallback(missing)}
      end
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp load_project(log, org_id) do
    Ash.get(Sitevoice.Projects.Project, log.project_id,
      tenant: org_id,
      authorize?: false
    )
  end

  defp do_run(log, project, missing) do
    case check_api_key() do
      :ok -> call_claude(log, project, missing)
      err -> err
    end
  end

  defp call_claude(log, project, missing) do
    prompt = build_user_prompt(log, project, missing)

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
            model: @model,
            max_tokens: @max_tokens,
            system: system_prompt(),
            messages: [%{role: "user", content: prompt}]
          },
          receive_timeout: @receive_timeout
        ] ++ Application.get_env(:sitevoice, :anthropic_req_options, [])
      )

    parse_response(result)
  end

  defp system_prompt do
    """
    You help construction foremen fill in gaps in their daily-log voice memos.
    Generate 1 to 3 short, specific questions tailored to the project context
    and the missing information. Each question should be brief enough that the
    foreman can answer it in a single short voice clip.

    Return ONLY a valid JSON array with this shape:
    [{"question": "...", "missing_field": "labor|progress|equipment|materials|delays|safety|weather|accuracy"}]

    No preamble, no fences.
    """
  end

  defp build_user_prompt(log, project, missing) do
    extracted = %{
      labor: log.labor,
      progress: log.progress,
      equipment: log.equipment,
      materials: log.materials,
      delays: log.delays,
      safety: log.safety,
      weather: log.weather,
      accuracy_score: log.accuracy_score
    }

    """
    PROJECT CONTEXT:
    #{project.daily_log_context}

    REQUIRED SECTIONS for this project: #{Enum.join(project.required_sections, ", ")}

    MISSING SECTIONS: #{Enum.join(missing, ", ")}

    TRANSCRIPT:
    #{log.transcript || ""}

    EXTRACTED SO FAR:
    #{Jason.encode!(extracted)}
    """
  end

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    with {:ok, list} when is_list(list) <- Jason.decode(t) do
      questions =
        list
        |> Enum.take(3)
        |> Enum.map(&normalize/1)
        |> Enum.filter(& &1)

      if questions == [] do
        {:error, :empty_questions}
      else
        {:ok, questions}
      end
    else
      {:ok, _} ->
        {:error, :unexpected_shape}

      {:error, decode_err} ->
        Logger.error("GenerateClarifications got invalid JSON from Claude: #{inspect(decode_err)}")
        {:error, decode_err}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}) do
    Logger.error("GenerateClarifications Claude HTTP #{s}: #{inspect(b) |> String.slice(0, 200)}")
    {:error, "HTTP #{s}"}
  end

  defp parse_response({:error, reason}) do
    Logger.error("GenerateClarifications request failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp normalize(%{"question" => q, "missing_field" => f}) when is_binary(q) and is_binary(f) do
    %{"question" => String.trim(q), "missing_field" => f}
  end

  defp normalize(%{"question" => q}) when is_binary(q) do
    %{"question" => String.trim(q), "missing_field" => "other"}
  end

  defp normalize(_), do: nil

  defp template_fallback(missing) do
    questions =
      missing
      |> Enum.map(&template_for/1)
      |> Enum.filter(& &1)
      |> Enum.take(3)

    if questions == [], do: [generic_template()], else: questions
  end

  defp template_for(:labor),
    do: %{"question" => "How many crew members were on site today and what trades?", "missing_field" => "labor"}

  defp template_for(:progress),
    do: %{"question" => "What work was completed today?", "missing_field" => "progress"}

  defp template_for(:safety),
    do: %{
      "question" => "Were there any safety incidents or near-misses today? Say 'none' if not.",
      "missing_field" => "safety"
    }

  defp template_for(:equipment),
    do: %{"question" => "What equipment was used or moved today?", "missing_field" => "equipment"}

  defp template_for(:materials),
    do: %{"question" => "Were any materials delivered or used today?", "missing_field" => "materials"}

  defp template_for(:delays),
    do: %{"question" => "Were there any delays today? Say 'none' if not.", "missing_field" => "delays"}

  defp template_for(:weather),
    do: %{"question" => "What was the weather like and did it affect work?", "missing_field" => "weather"}

  defp template_for(:accuracy), do: generic_template()
  defp template_for(_), do: nil

  defp generic_template,
    do: %{
      "question" => "Can you briefly summarize the key activities for the day?",
      "missing_field" => "accuracy"
    }

  defp check_api_key do
    case Application.fetch_env(:sitevoice, :anthropic_api_key) do
      {:ok, key} when is_binary(key) and key != "" -> :ok
      _ -> {:error, :no_api_key}
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
