# Tasks — Slice 07: Notifications

Work through in order. Check off each task as it is completed.

---

## 1. Create DailyLogEmail Module

File: `lib/sitevoice/reporting/emails/daily_log_email.ex`

- [x] Define `Sitevoice.Reporting.Emails.DailyLogEmail`
- [x] `import Swoosh.Email`
- [x] Implement `report_ready(log, pdf_binary, pm)`:
  - [x] `to: {pm.name, to_string(pm.email)}` (CiString → plain string)
  - [x] `from: {"SiteVoice AI", "reports@sitevoice.app"}`
  - [x] `subject: "Daily Log — #{log.project.name} · #{log.date}"`
  - [x] `text_body: "Daily site report for #{log.date} is ready. See attached PDF."`
  - [x] Attach PDF via `Swoosh.Attachment.new({:data, pdf_binary}, filename: ..., content_type: "application/pdf")`
- [x] Implement `daily_reminder(foreman)`:
  - [x] `to: {foreman.name, to_string(foreman.email)}`
  - [x] `from: {"SiteVoice AI", "reminders@sitevoice.app"}`
  - [x] `subject: "Reminder: Submit your daily log for #{Date.utc_today()}"`
  - [x] `text_body: "Hi #{foreman.name}, don't forget to submit your daily site log today."`

## 2. Create EnqueueNotification Change

File: `lib/sitevoice/reporting/changes/enqueue_notification.ex`

- [x] Define `Sitevoice.Reporting.Changes.EnqueueNotification` with `use Ash.Resource.Change`
- [x] Implement `change(changeset, _, _)`:
  - [x] Use `Ash.Changeset.after_action/2`
  - [x] Inside callback: build `%{log_id: log.id, organization_id: log.organization_id}`
  - [x] Pipe through `Sitevoice.Workers.NotifyPmWorker.new()` then `Oban.insert()`
  - [x] Return `{:ok, log}`

## 3. Wire EnqueueNotification into DailyLog

File: `lib/sitevoice/reporting/daily_log.ex`

- [x] Add `change Sitevoice.Reporting.Changes.EnqueueNotification` to `:approve_and_submit` action

## 4. Create NotifyPmWorker

File: `lib/sitevoice/workers/notify_pm_worker.ex`

- [x] Define `Sitevoice.Workers.NotifyPmWorker` with `use Oban.Worker, queue: :notifications, max_attempts: 3`
- [x] Implement `perform/1` with explicit `tenant: org_id` on every Ash call
- [x] Guard: return `{:error, :no_pdf}` when `log.pdf_key` is nil
- [x] Filter PM memberships, load User records, fetch PDF from Tigris, deliver email per PM

## 5. Create DailyReminderWorker

File: `lib/sitevoice/workers/daily_reminder_worker.ex`

- [x] Define `Sitevoice.Workers.DailyReminderWorker` with `use Oban.Worker, queue: :notifications, max_attempts: 3`
- [x] `require Ash.Query`
- [x] `perform/1` lists all active orgs (global query), for each org sets tenant and checks each foreman
- [x] Sends `daily_reminder` email to foremen with no submitted log today

## 6. Update Oban Cron Config

File: `config/config.exs`

- [x] Replace `{Oban.Plugins.Cron, []}` with `{Oban.Plugins.Cron, crontab: [{"0 6 * * *", Sitevoice.Workers.DailyReminderWorker}]}`

## 7. Configure Resend Adapter for Production

File: `config/runtime.exs`

- [x] Added `config :sitevoice, Sitevoice.Mailer, adapter: Swoosh.Adapters.Resend, api_key: System.fetch_env!("RESEND_API_KEY")` inside prod block

## 8. Write DailyLogEmail Tests

File: `test/sitevoice/reporting/emails/daily_log_email_test.exs`

- [x] Tag `@moduletag slice: :notifications`
- [x] Test `report_ready/3`: subject, from, to, attachment filename, content type
- [x] Test `daily_reminder/1`: subject contains "Reminder", from, to, body contains foreman name

## 9. Write NotifyPmWorker Tests

File: `test/sitevoice/workers/notify_pm_worker_test.exs`

- [x] Tag `@moduletag slice: :notifications`
- [x] `use Oban.Testing, repo: Sitevoice.Repo`
- [x] Test happy path: email sent to PM when log has pdf_key
- [x] Test `{:error, :no_pdf}` when pdf_key is nil
- [x] Test no email sent when project has no PM members
- [x] `drain_mailbox/0` helper clears setup confirmation emails before assertions

## 10. Write DailyReminderWorker Tests

File: `test/sitevoice/workers/daily_reminder_worker_test.exs`

- [x] Tag `@moduletag slice: :notifications`
- [x] `use Oban.Testing, repo: Sitevoice.Repo`
- [x] Test reminder sent to foreman with no submitted log today
- [x] Test no reminder sent to foreman who has already submitted today
- [x] `drain_mailbox/0` helper clears setup confirmation emails before assertions

## 11. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:notifications` — all 9 tests pass
- [x] `mix test` — 101 tests, 0 failures (no regressions)
