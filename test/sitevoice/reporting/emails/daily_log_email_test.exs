defmodule Sitevoice.Reporting.Emails.DailyLogEmailTest do
  use ExUnit.Case, async: true

  @moduletag slice: :notifications

  alias Sitevoice.Reporting.Emails.DailyLogEmail

  describe "report_ready/3" do
    test "builds email with correct to, from, and subject" do
      log = %{project: %{name: "Riverside Tower"}, date: ~D[2025-05-14]}
      pm = %{name: "Jane PM", email: "jane@example.com"}

      email = DailyLogEmail.report_ready(log, "fake-pdf-binary", pm)

      assert email.subject == "Daily Log — Riverside Tower · 2025-05-14"
      assert email.from == {"SiteVoice AI", "reports@sitevoice.app"}
      assert email.to == [{"Jane PM", "jane@example.com"}]
    end

    test "attaches PDF with correct filename and content type" do
      log = %{project: %{name: "Riverside Tower"}, date: ~D[2025-05-14]}
      pm = %{name: "Jane PM", email: "jane@example.com"}

      email = DailyLogEmail.report_ready(log, "fake-pdf-binary", pm)

      assert [attachment] = email.attachments
      assert attachment.filename == "daily-log-2025-05-14.pdf"
      assert attachment.content_type == "application/pdf"
      assert attachment.data == "fake-pdf-binary"
    end
  end

  describe "daily_reminder/1" do
    test "builds reminder email addressed to the foreman" do
      foreman = %{name: "Bob Foreman", email: "bob@example.com"}

      email = DailyLogEmail.daily_reminder(foreman)

      assert email.subject =~ "Reminder"
      assert email.from == {"SiteVoice AI", "reminders@sitevoice.app"}
      assert email.to == [{"Bob Foreman", "bob@example.com"}]
    end

    test "includes foreman name in text body" do
      foreman = %{name: "Bob Foreman", email: "bob@example.com"}

      email = DailyLogEmail.daily_reminder(foreman)

      assert email.text_body =~ "Bob Foreman"
    end
  end
end
