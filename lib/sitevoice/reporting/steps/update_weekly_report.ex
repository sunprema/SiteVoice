defmodule Sitevoice.Steps.UpdateWeeklyReport do
  use Reactor.Step

  require Logger

  def run(%{report: report, aggregated: agg, synthesized: synth, pdf_key: pdf_key, organization_id: org_id}, _, _) do
    Logger.info("UpdateWeeklyReport marking ready", report_id: report.id)

    attrs = %{
      summary: synth.summary,
      key_accomplishments: synth.key_accomplishments,
      outstanding_issues: synth.outstanding_issues,
      trends: synth.trends,
      pdf_key: pdf_key,
      total_labor_hours: agg.total_labor_hours,
      total_headcount_days: agg.total_headcount_days,
      daily_log_count: agg.daily_log_count,
      generated_at: DateTime.utc_now()
    }

    result =
      report
      |> Ash.Changeset.for_update(:mark_ready, attrs, authorize?: false, tenant: org_id)
      |> Ash.update()

    case result do
      {:ok, updated} ->
        broadcast(org_id, report.id, :ready)
        Logger.info("UpdateWeeklyReport succeeded", report_id: report.id)
        {:ok, updated}

      {:error, reason} ->
        Logger.error("UpdateWeeklyReport failed", report_id: report.id, reason: inspect(reason))
        {:error, reason}
    end
  end

  def compensate(%{report: report, organization_id: org_id}, _, _, _) do
    Logger.warning("UpdateWeeklyReport compensating — marking report failed", report_id: report.id)

    report
    |> Ash.Changeset.for_update(:mark_failed, %{}, authorize?: false, tenant: org_id)
    |> Ash.update()

    broadcast(org_id, report.id, :failed)
    :ok
  end

  defp broadcast(org_id, report_id, status) do
    Phoenix.PubSub.broadcast(
      Sitevoice.PubSub,
      "org:#{org_id}:weekly_report:#{report_id}",
      {:weekly_report_status, %{report_id: report_id, status: status}}
    )
  end
end
