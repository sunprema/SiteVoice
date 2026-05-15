# Context — Slice 07: Notifications

## Dependency

Slice 06 (Real-time Channels) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §15.2 — Email (Swoosh): `DailyLogEmail.report_ready/3`, PDF attachment
2. `docs/APPLICATION_SPEC.md` §9.2 — Oban Queues: `notifications: 20`, `DailyReminderWorker` cron
3. `docs/APPLICATION_SPEC.md` §6.5 — Oban Jobs: tenant propagation in `perform/1`
4. `docs/APPLICATION_SPEC.md` §5.3 — `DailyLog` resource: `:approve_and_submit` action, `foreman_id`, `project_id`
5. `docs/CODING_STANDARDS.md` — Oban worker conventions, Changes file location
6. `CLAUDE.md` — Architecture Rules §Multitenancy, §Oban

## Existing State

- `lib/sitevoice/mailer.ex` — `Sitevoice.Mailer` already exists (`use Swoosh.Mailer, otp_app: :sitevoice`)
- `config/config.exs` — Oban config has `notifications: 10` queue and `plugins: [{Oban.Plugins.Cron, []}]` (cron table is empty — needs `DailyReminderWorker` wired in)
- `config/prod.exs` — `config :swoosh, api_client: Swoosh.ApiClient.Req` already set
- `config/runtime.exs` — Resend adapter not yet configured (commented out); needs production wiring
- `lib/sitevoice/reporting/daily_log.ex` — `:approve_and_submit` action exists; needs `EnqueueNotification` change added
- `lib/sitevoice/reporting/steps/broadcast_ready.ex` — broadcasts `{:report_ready, ...}` via PubSub (already complete; not modified in this slice)
- `lib/sitevoice/projects/project_membership.ex` — `ProjectMembership` resource with roles; used to find PM users for a project

## New Files To Create

### Email

- `lib/sitevoice/reporting/emails/daily_log_email.ex` — Swoosh email template
  - `report_ready(log, pdf_binary, pm)` — PDF attached, subject includes project name and date
  - `daily_reminder(foreman)` — short text reminder to submit today's log

### Oban Workers

- `lib/sitevoice/workers/notify_pm_worker.ex` — sends PDF email to all PMs on the project
  - Queue: `:notifications`, `max_attempts: 3`
  - Job args: `%{"log_id" => ..., "organization_id" => ...}`

# pass tenant to every Ash call

- Fetches DailyLog (with `foreman`, `project`, `organization` loaded)
- Fetches PM members of the project via `ProjectMembership` (role: `:pm`)
- Fetches PM `User` records for their email addresses
- Fetches PDF binary from Tigris via `Sitevoice.Storage.fetch/2` with the pdf bucket
- Sends email to each PM via `Sitevoice.Mailer.deliver/1`

- `lib/sitevoice/workers/daily_reminder_worker.ex` — cron job, runs globally at 6 AM UTC
  - Queue: `:notifications`, `max_attempts: 3`
  - `perform/1` receives no user-facing args (cron-triggered)
  - Query all active `Organization` records (global — no tenant)
  - For each org: set tenant, find foremen with no `:submitted` `DailyLog` for today
  - Send `daily_reminder/1` email to each such foreman via `Sitevoice.Mailer.deliver/1`

### Ash Change

- `lib/sitevoice/reporting/changes/enqueue_notification.ex` — `Ash.Resource.Change`
  - `change/3` calls `Ash.Changeset.after_action/2`
  - Enqueues `Sitevoice.Workers.NotifyPmWorker` with `%{log_id: log.id, organization_id: log.organization_id}`

### Tests

- `test/sitevoice/reporting/emails/daily_log_email_test.exs`
- `test/sitevoice/workers/notify_pm_worker_test.exs`
- `test/sitevoice/workers/daily_reminder_worker_test.exs`

## Existing Files To Modify

- `lib/sitevoice/reporting/daily_log.ex`
  - Add `change Sitevoice.Reporting.Changes.EnqueueNotification` to the `:approve_and_submit` action

- `config/config.exs`
  - Update `{Oban.Plugins.Cron, []}` to include `crontab: [{"0 6 * * *", Sitevoice.Workers.DailyReminderWorker}]`

- `config/runtime.exs`
  - Uncomment / add Resend adapter config for production:
    ```elixir
    config :sitevoice, Sitevoice.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: System.fetch_env!("RESEND_API_KEY")
    ```

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention

# pass tenant to every Ash call

- `DailyReminderWorker` is a global cron worker: it has no `organization_id` in job args. It fetches all orgs without a tenant, then sets tenant per org inside the iteration loop
- Job args for `NotifyPmWorker` must include `organization_id` (required by architecture rules)
- Email tests use Swoosh test adapter (`config :swoosh, :api_client, false` — already set in `test.exs`); use `assert_email_sent` from `Swoosh.TestAssertions`
- Oban worker tests use `Oban.Testing` (`use Oban.Testing, repo: Sitevoice.Repo`) and `perform_job/2`
- Req.Test stubs required for Tigris fetch calls in `NotifyPmWorker` tests — never hit real storage in tests
- `DailyReminderWorker` iterates orgs — in tests, create at least one org + foreman without a log and assert email sent
- All tests tagged `@moduletag slice: :notifications`
- `mix compile --warnings-as-errors` — zero warnings
- `require Ash.Query` wherever `Ash.Query` macros (like `filter/2`) are used
