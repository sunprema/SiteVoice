defmodule Sitevoice.Steps.SynthesizeWeeklySummary do
  use Reactor.Step

  require Logger

  @system_prompt """
  You are a construction project reporting assistant. Analyze the weekly site activity data
  and return ONLY valid JSON with these keys:
  - "summary": 2-3 paragraph executive narrative (string)
  - "key_accomplishments": list of concise strings, max 8 items
  - "outstanding_issues": list of concise strings, max 5 items
  - "trends": list of objects with keys "description" (string) and "severity" ("low"|"medium"|"high")

  If no logs were submitted, note that in the summary and return empty lists for the other fields.
  Return ONLY valid JSON. No markdown. No preamble.
  """

  def run(%{aggregated: data, report: report}, _, _) do
    with :ok <- check_api_key() do
      do_run(data, report)
    end
  end

  defp do_run(data, report) do
    prompt = build_prompt(data, report)

    Logger.info("SynthesizeWeeklySummary calling Claude",
      week_start: report.week_start,
      log_count: data.daily_log_count
    )

    :telemetry.span(
      [:sitevoice, :claude, :weekly_summary],
      %{log_count: data.daily_log_count},
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
                max_tokens: 1500,
                system: @system_prompt,
                messages: [%{role: "user", content: prompt}]
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

  defp build_prompt(data, report) do
    progress_lines = format_list(data.progress, &("- #{&1["description"]} at #{&1["location"]} (#{&1["percentage_complete"]}% complete)"))
    labor_lines = format_list(data.labor_by_trade, &("- #{&1["trade"]}: #{&1["total_headcount"]} workers, #{&1["total_hours"]}h total"))
    delay_lines = format_list(data.delays, &("- #{&1["description"] || &1["reason"]} (#{&1["hours_lost"] || &1["duration"]} hours lost)"))
    safety_lines = format_list(data.safety, &("- #{&1["description"] || &1["observation"]}"))
    materials_lines = format_list(data.materials, &("- #{&1["item"] || &1["material"]}: #{&1["quantity"]}"))
    equipment_lines = format_list(data.equipment, &("- #{&1["item"]} [#{&1["status"]}]"))
    weather_line = if data.weather == [], do: "Not recorded", else: Enum.join(data.weather, "; ")

    """
    Week: #{report.week_start} to #{report.week_end}
    Days with submitted logs: #{data.daily_log_count} of 5

    PROGRESS ITEMS:
    #{if progress_lines == "", do: "None recorded", else: progress_lines}

    LABOR SUMMARY:
    Total: #{data.total_headcount_days} worker-days, #{data.total_labor_hours}h across all trades
    #{if labor_lines == "", do: "None recorded", else: labor_lines}

    DELAYS:
    #{if delay_lines == "", do: "None", else: delay_lines}

    SAFETY OBSERVATIONS:
    #{if safety_lines == "", do: "None", else: safety_lines}

    MATERIALS RECEIVED:
    #{if materials_lines == "", do: "None recorded", else: materials_lines}

    EQUIPMENT:
    #{if equipment_lines == "", do: "None recorded", else: equipment_lines}

    WEATHER: #{weather_line}
    """
  end

  defp format_list([], _), do: ""
  defp format_list(items, format_fn) do
    items
    |> Enum.map(fn item ->
      try do
        format_fn.(item)
      rescue
        _ -> "- #{inspect(item)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    case Jason.decode(t) do
      {:ok, data} ->
        result = %{
          summary: data["summary"] || "",
          key_accomplishments: data["key_accomplishments"] || [],
          outstanding_issues: data["outstanding_issues"] || [],
          trends: data["trends"] || []
        }

        Logger.info("SynthesizeWeeklySummary succeeded",
          accomplishments: length(result.key_accomplishments),
          issues: length(result.outstanding_issues),
          trends: length(result.trends)
        )

        {:ok, result}

      {:error, decode_err} ->
        raw_preview = String.slice(t, 0, 500)
        Logger.error("SynthesizeWeeklySummary invalid JSON — #{inspect(decode_err)} raw=#{raw_preview}")
        {:error, "Invalid JSON from Claude: #{inspect(decode_err)}"}
    end
  end

  defp parse_response({:ok, %{status: s, body: b}}) do
    body_preview = b |> inspect() |> String.slice(0, 300)
    Logger.error("SynthesizeWeeklySummary API error — status=#{s} body=#{body_preview}")
    {:error, "Claude HTTP #{s}: #{body_preview}"}
  end

  defp parse_response({:error, %{reason: reason}}) do
    Logger.error("SynthesizeWeeklySummary request failed — #{inspect(reason)}")
    {:error, "Claude connection error: #{inspect(reason)}"}
  end

  defp parse_response({:error, r}) do
    Logger.error("SynthesizeWeeklySummary request failed — #{inspect(r)}")
    {:error, r}
  end

  defp check_api_key do
    case Application.fetch_env(:sitevoice, :anthropic_api_key) do
      {:ok, key} when is_binary(key) and key != "" -> :ok
      _ -> {:error, "Anthropic API key not configured"}
    end
  end

  defp api_key, do: Application.fetch_env!(:sitevoice, :anthropic_api_key)
end
