defmodule Sitevoice.Reporting do
  use Ash.Domain,
    otp_app: :sitevoice

  resources do
    resource Sitevoice.Reporting.DailyLog do
      define :get_log, action: :read, get_by: [:id]
      define :start_log, action: :start_log
      define :submit_recording, action: :submit_recording
      define :submit_text_report, action: :submit_text_report
      define :submit_entries, action: :submit_entries
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

    resource Sitevoice.Reporting.LogEntry do
      define :add_voice_memo, action: :add_voice_memo
      define :add_text_note, action: :add_text_note
      define :add_photo_entry, action: :add_photo
      define :list_entries_for_log, action: :for_log, args: [:daily_log_id]
      define :remove_entry, action: :remove_entry
    end

    resource Sitevoice.Reporting.CrewTemplate do
      define :create_crew_template, action: :create
      define :update_crew_template, action: :update
      define :list_crew_templates, action: :list_for_project, args: [:project_id]
      define :list_all_crew_templates, action: :list_all_for_project, args: [:project_id]
    end

    resource Sitevoice.Reporting.DailyAttendance do
      define :list_attendances_for_log, action: :list_for_log, args: [:daily_log_id]
      define :update_attendance, action: :update_attendance
    end

    resource Sitevoice.Reporting.WeeklyReport do
      define :list_weekly_reports_for_project, action: :list_for_project, args: [:project_id]
      define :get_weekly_report_by_week, action: :get_by_week, args: [:project_id, :week_start]
    end
  end
end
