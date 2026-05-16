defmodule Sitevoice.Reporting.Reactors.GenerateWeeklyReport do
  use Ash.Reactor

  input :report_id
  input :organization_id

  step :set_tenant, Sitevoice.Steps.SetTenant do
    argument :organization_id, input(:organization_id)
  end

  step :fetch_report, Sitevoice.Steps.FetchWeeklyReport do
    argument :report_id, input(:report_id)
    argument :organization_id, input(:organization_id)
    wait_for :set_tenant
  end

  step :fetch_weekly_logs, Sitevoice.Steps.FetchWeeklyLogs do
    argument :report, result(:fetch_report)
    argument :organization_id, input(:organization_id)
    wait_for :fetch_report
  end

  step :aggregate_log_data, Sitevoice.Steps.AggregateLogData do
    argument :logs, result(:fetch_weekly_logs)
    argument :report, result(:fetch_report)
    wait_for :fetch_weekly_logs
  end

  step :synthesize_weekly_summary, Sitevoice.Steps.SynthesizeWeeklySummary do
    argument :aggregated, result(:aggregate_log_data)
    argument :report, result(:fetch_report)
    wait_for :aggregate_log_data
  end

  step :generate_weekly_pdf, Sitevoice.Steps.GenerateWeeklyPdf do
    argument :report, result(:fetch_report)
    argument :aggregated, result(:aggregate_log_data)
    argument :synthesized, result(:synthesize_weekly_summary)
    wait_for :synthesize_weekly_summary
  end

  step :store_weekly_pdf, Sitevoice.Steps.StoreWeeklyPdf do
    argument :binary, result(:generate_weekly_pdf)
    argument :report_id, input(:report_id)
    argument :organization_id, input(:organization_id)
    wait_for :generate_weekly_pdf
  end

  step :update_weekly_report, Sitevoice.Steps.UpdateWeeklyReport do
    argument :report, result(:fetch_report)
    argument :aggregated, result(:aggregate_log_data)
    argument :synthesized, result(:synthesize_weekly_summary)
    argument :pdf_key, result(:store_weekly_pdf)
    argument :organization_id, input(:organization_id)
    wait_for :store_weekly_pdf
  end
end
