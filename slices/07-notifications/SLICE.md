# Slice 07 — Notifications

**Goal:** Deliver two notification types: (1) email the completed PDF daily log to every PM on the
project when a report is approved and submitted, and (2) send a daily 6 AM reminder email to
foremen who haven't yet submitted a log for the day. Both paths run through Oban workers on the
`:notifications` queue, keeping request handlers free of blocking I/O.

## Acceptance Criteria

- [ ] `Sitevoice.Reporting.Emails.DailyLogEmail.report_ready/3` builds a Swoosh email with the PDF
      binary attached (filename `daily-log-{date}.pdf`, content type `application/pdf`), addressed
      to the PM, from `reports@sitevoice.app`, subject `"Daily Log — {project_name} · {date}"`
- [ ] `Sitevoice.Reporting.Emails.DailyLogEmail.daily_reminder/1` builds a Swoosh email addressed
      to the foreman with a short text body prompting them to submit today's log
- [ ] `Sitevoice.Workers.NotifyPmWorker` uses queue `:notifications`, `max_attempts: 3`; `perform/1`

# pass tenant to every Ash call

      `[foreman: [], project: [], organization: []]`; fetches all PM `ProjectMembership` records for
      the project; fetches their `User` records; fetches the PDF binary from Tigris; delivers one
      email per PM via `Sitevoice.Mailer.deliver/1`; returns `:ok`

- [ ] `Sitevoice.Reporting.Changes.EnqueueNotification` enqueues `NotifyPmWorker` in an
      `after_action` callback on the `:approve_and_submit` action with args
      `%{log_id: log.id, organization_id: log.organization_id}`
- [ ] `Sitevoice.Reporting.DailyLog` `:approve_and_submit` action includes
      `change Sitevoice.Reporting.Changes.EnqueueNotification`
- [ ] `Sitevoice.Workers.DailyReminderWorker` uses queue `:notifications`, `max_attempts: 3`;
      `perform/1` queries all active `Organization` records (no tenant set at global level); for each

# pass tenant to every Ash call

      who have no `DailyLog` with status `:submitted` for `Date.utc_today()`; delivers
      `daily_reminder/1` email to each such foreman; returns `:ok`

- [ ] Oban cron in `config/config.exs` includes `{"0 6 * * *", Sitevoice.Workers.DailyReminderWorker}`
- [ ] `config/runtime.exs` configures `Sitevoice.Mailer` with `Swoosh.Adapters.Resend` and
      `RESEND_API_KEY` env var in the production block
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:notifications` — all tests pass
- [ ] `mix test` — no regressions in slices 00–06

## What This Slice Does NOT Include

- Push notifications (APNs / FCM) to mobile devices — post-MVP
- Slack / Teams integration (Slice 08 / post-MVP)
- Procore dispatch (Slice 08)
- In-app notification centre or read/unread tracking
- Email preferences or opt-out per user
- React Native notification handling (Slice 09)

## Key Behaviours

### NotifyPmWorker Flow

```
perform(%{log_id, organization_id})
  → set_tenant(org_id)
  → load DailyLog with [:foreman, :project, :organization]
  → load ProjectMembership where project_id = log.project_id and role = :pm
  → load User records for each membership
  → fetch PDF binary from Tigris (pdf bucket, log.pdf_key)
  → for each PM: build email, deliver via Mailer
  → :ok
```

If the log has no `pdf_key`, return `{:error, :no_pdf}` so Oban retries.

### DailyReminderWorker Flow

```
perform(_)
  → list all active Organizations (no tenant — global query)
  → for each org:
      set_tenant(org.id)
      find Users where role == :foreman
      for each foreman:
        if no DailyLog submitted today for this foreman → send daily_reminder email
  → :ok
```

### EnqueueNotification Change

```elixir
defmodule Sitevoice.Reporting.Changes.EnqueueNotification do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _cs, log ->
      %{log_id: log.id, organization_id: log.organization_id}
      |> Sitevoice.Workers.NotifyPmWorker.new()
      |> Oban.insert()
      {:ok, log}
    end)
  end
end
```

### Tenant Rules

# pass tenant to every Ash call

# pass tenant to every Ash call

- All Ash reads in workers must pass `authorize?: false` (no actor in background jobs)

### Email Spec

```elixir
# report_ready/3
new()
|> to({pm.name, pm.email})
|> from({"SiteVoice AI", "reports@sitevoice.app"})
|> subject("Daily Log — #{log.project.name} · #{log.date}")
|> text_body("Daily site report for #{log.date} is ready. See attached PDF.")
|> attachment(%Swoosh.Attachment{
    filename:     "daily-log-#{log.date}.pdf",
    content:      pdf_binary,
    content_type: "application/pdf"
  })

# daily_reminder/1
new()
|> to({foreman.name, foreman.email})
|> from({"SiteVoice AI", "reminders@sitevoice.app"})
|> subject("Reminder: Submit your daily log for #{Date.utc_today()}")
|> text_body("Hi #{foreman.name}, don't forget to submit your daily site log today.")
```
