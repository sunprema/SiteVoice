defmodule Sitevoice.Steps.GenerateWeeklyPdf do
  use Reactor.Step

  require Logger

  @imprintor Application.compile_env(:sitevoice, :imprintor_mod, Imprintor)

  def run(%{report: report, aggregated: agg, synthesized: synth}, _, _) do
    Logger.info("GenerateWeeklyPdf starting",
      report_id: report.id,
      week_start: report.week_start
    )

    template = File.read!(Application.app_dir(:sitevoice, "priv/templates/weekly_report.typ"))

    data = %{
      "organization" => report.organization.name,
      "project" => report.project.name,
      "week_start" => Date.to_string(report.week_start),
      "week_end" => Date.to_string(report.week_end),
      "generated_at" => Calendar.strftime(DateTime.utc_now(), "%B %d, %Y"),
      "daily_log_count" => agg.daily_log_count,
      "total_labor_hours" => agg.total_labor_hours,
      "total_headcount_days" => agg.total_headcount_days,
      "labor_by_trade" => agg.labor_by_trade,
      "daily_snapshot" => agg.daily_snapshot,
      "weather" => Enum.join(agg.weather, ", "),
      "summary" => synth.summary,
      "key_accomplishments" => synth.key_accomplishments,
      "outstanding_issues" => synth.outstanding_issues,
      "trends" => synth.trends
    }

    config = Imprintor.Config.new(template, data)

    :telemetry.span([:sitevoice, :pdf, :generate_weekly], %{report_id: report.id}, fn ->
      result =
        case @imprintor.compile_to_pdf(config) do
          {:ok, binary} ->
            Logger.info("GenerateWeeklyPdf succeeded",
              report_id: report.id,
              pdf_bytes: byte_size(binary)
            )
            {:ok, binary}

          {:error, reason} ->
            Logger.error("GenerateWeeklyPdf failed — report=#{report.id} reason=#{inspect(reason)}")
            {:error, "PDF compilation failed: #{inspect(reason)}"}
        end

      {result, %{}}
    end)
  end

  def compensate(_, _, _, _), do: :ok
end
