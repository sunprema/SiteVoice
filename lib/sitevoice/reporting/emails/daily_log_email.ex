defmodule Sitevoice.Reporting.Emails.DailyLogEmail do
  import Swoosh.Email

  def report_ready(log, pdf_binary, pm) do
    new()
    |> to({pm.name, to_string(pm.email)})
    |> from({"SiteVoice AI", "reports@sitevoice.app"})
    |> subject("Daily Log — #{log.project.name} · #{log.date}")
    |> text_body("Daily site report for #{log.date} is ready. See attached PDF.")
    |> attachment(
        Swoosh.Attachment.new(
          {:data, pdf_binary},
          filename: "daily-log-#{log.date}.pdf",
          content_type: "application/pdf"
        )
      )
  end

  def daily_reminder(foreman) do
    new()
    |> to({foreman.name, to_string(foreman.email)})
    |> from({"SiteVoice AI", "reminders@sitevoice.app"})
    |> subject("Reminder: Submit your daily log for #{Date.utc_today()}")
    |> text_body("Hi #{foreman.name}, don't forget to submit your daily site log today.")
  end
end
