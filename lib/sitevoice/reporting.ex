defmodule Sitevoice.Reporting do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Reporting.DailyLog do
      define :get_log, action: :read, get_by: [:id]
      define :submit_recording, action: :submit_recording
      define :submit_text_report, action: :submit_text_report
      define :approve_and_submit, action: :approve_and_submit
      define :list_logs_for_project, action: :list_for_project, args: [:project_id]
      define :list_logs, action: :list_all, args: [:project_id, :status]
      define :get_today_log_for_foreman, action: :get_today_for_foreman, args: [:foreman_id, :date]
      define :list_logs_for_foreman, action: :list_for_foreman, args: [:foreman_id]
      define :list_logs_for_date, action: :list_for_date, args: [:date]
    end

    resource Sitevoice.Reporting.DailyLog.Version

    resource Sitevoice.Reporting.Photo do
      define :upload_photo, action: :upload, args: [:storage_key, :daily_log_id]
    end
  end
end
