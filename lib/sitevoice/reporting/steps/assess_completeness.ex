defmodule Sitevoice.Steps.AssessCompleteness do
  @moduledoc """
  Decides whether a freshly extracted DailyLog has enough information to skip
  straight to PDF generation, or whether the foreman should be asked one round
  of clarification questions.

  The decision is project-driven: each Project carries `required_sections` and
  `daily_log_min_accuracy`. The log itself is also consulted — if it already
  ran one clarification round we never trigger again (hard cap).
  """

  use Reactor.Step

  require Logger

  def run(%{log: log, organization_id: org_id}, _, _) do
    case Ash.get(Sitevoice.Projects.Project, log.project_id,
           tenant: org_id,
           authorize?: false
         ) do
      {:ok, project} ->
        assess(log, project)

      {:error, reason} ->
        Logger.error("AssessCompleteness could not load project",
          log_id: log.id,
          project_id: log.project_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def compensate(_, _, _, _), do: :ok

  defp assess(log, project) do
    cond do
      log.clarification_round >= 1 ->
        Logger.info("AssessCompleteness cap reached, marking complete",
          log_id: log.id,
          clarification_round: log.clarification_round
        )

        {:ok, []}

      true ->
        missing = collect_missing(log, project)

        if missing == [] do
          Logger.info("AssessCompleteness: log is complete", log_id: log.id)
        else
          Logger.info("AssessCompleteness: log is incomplete",
            log_id: log.id,
            missing: missing
          )
        end

        {:ok, missing}
    end
  end

  defp collect_missing(log, project) do
    section_misses =
      Enum.filter(project.required_sections, fn section ->
        section_empty?(log, section)
      end)

    accuracy_miss =
      if accuracy_below_threshold?(log, project), do: [:accuracy], else: []

    section_misses ++ accuracy_miss
  end

  defp section_empty?(log, :weather) do
    case log.weather do
      nil -> true
      "" -> true
      s when is_binary(s) -> String.trim(s) == ""
      _ -> false
    end
  end

  defp section_empty?(log, section) do
    case Map.get(log, section) do
      nil -> true
      [] -> true
      _ -> false
    end
  end

  defp accuracy_below_threshold?(log, project) do
    case log.accuracy_score do
      nil -> false
      score -> score < project.daily_log_min_accuracy
    end
  end
end
