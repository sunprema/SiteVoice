# Context — Slice 12: Weekly Report

## Dependency

Slices 04 (AI Pipeline), 05 (PDF Generation), 07 (Notifications), and 08 (LiveView) must be
complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `lib/sitevoice/reporting/daily_log.ex` — DailyLog resource; note `list_for_date_range` action
   (accepts `project_id`, `from`, `to`), and the structured fields: `labor`, `progress`,
   `equipment`, `materials`, `delays`, `safety`, `weather`
2. `lib/sitevoice/reporting/steps/structure_with_claude.ex` — pattern for Claude API calls
3. `lib/sitevoice/reporting/steps/generate_pdf.ex` — Imprintor PDF generation pattern
4. `lib/sitevoice/reporting/steps/store_tigris.ex` — Tigris upload pattern
5. `lib/sitevoice/reporting/reactors/process_recording.ex` — Reactor composition pattern
6. `lib/sitevoice/reporting/emails/daily_log_email.ex` — Email module pattern
7. `lib/sitevoice/workers/notify_pm_worker.ex` — Oban worker with tenant propagation
8. `lib/sitevoice_web/live/logs/index_live.ex` — LiveView list page pattern
9. `docs/CODING_STANDARDS.md` — file layout, naming conventions
10. `CLAUDE.md` — Architecture Rules §Multitenancy, §Reactor, §Oban

## Existing State

- `lib/sitevoice/reporting/daily_log.ex` — `:list_for_date_range` action already exists; no
  changes needed to DailyLog
- `config/config.exs` — Oban cron already configured with `DailyReminderWorker`; needs
  `WeeklyReportSchedulerWorker` added
- `lib/sitevoice/reporting/` — domain home for new `WeeklyReport` resource and new reactor
- `lib/sitevoice/workers/` — home for new Oban workers
- `priv/typst/` — home for new `weekly_report.typ` Typst template
- `lib/sitevoice_web/live/` — home for new LiveView

## New Files To Create

### Ash Resource

- `lib/sitevoice/reporting/weekly_report.ex` — `Sitevoice.Reporting.WeeklyReport`
  - Multitenancy: attribute strategy on `organization_id`
  - Attributes: `project_id`, `week_start` (date, Monday), `week_end` (date, Sunday), `status`
    (atom: `pending | generating | ready | failed`), `summary` (string), `key_accomplishments`
    (array of string), `outstanding_issues` (array of string), `trends` (array of map),
    `total_labor_hours` (float), `total_headcount_days` (integer), `daily_log_count` (integer),
    `pdf_key` (string), `generated_at` (utc_datetime)
  - Actions: `:create` (internal, creates pending record), `:mark_generating`, `:mark_ready`
    (accepts summary fields + pdf_key), `:mark_failed`, `:read`, `:list_for_project`
    (filter by project_id, sort by week_start desc), `:get_by_week` (filter by project_id +
    week_start, get? true)
  - Policies: background workers (`actor_absent`) and `org_admin` for mutations; `:pm`, `:owner`,
    `:org_admin` for reads

### Ash Reactor Steps

- `lib/sitevoice/reporting/steps/fetch_weekly_logs.ex` — calls `DailyLog.list_for_date_range`
  with tenant; returns list of submitted logs (filters to status `:submitted`)
- `lib/sitevoice/reporting/steps/aggregate_log_data.ex` — pure Elixir step; aggregates labor
  hours and headcount, collects all progress/equipment/materials/delays/safety/weather items
  across the week's logs; returns a structured map used by the Claude and PDF steps
- `lib/sitevoice/reporting/steps/synthesize_weekly_summary.ex` — calls Claude API with
  aggregated data map; returns `%{summary: string, key_accomplishments: [string],
  outstanding_issues: [string], trends: [map]}`
- `lib/sitevoice/reporting/steps/generate_weekly_pdf.ex` — calls Imprintor with
  `weekly_report.typ` template, passing aggregated data + Claude output
- `lib/sitevoice/reporting/steps/store_weekly_pdf.ex` — uploads PDF binary to Tigris under
  `{org_id}/weekly-reports/{report_id}.pdf`
- `lib/sitevoice/reporting/steps/update_weekly_report.ex` — updates `WeeklyReport` to `:ready`
  with all output fields

### Ash Reactor

- `lib/sitevoice/reporting/reactors/generate_weekly_report.ex` — `Sitevoice.Reporting.Reactors.GenerateWeeklyReport`
  - Inputs: `report_id`, `organization_id`
  - Steps (in order): `SetTenant` → `fetch_log` (fetch WeeklyReport record) →
    `fetch_weekly_logs` → `aggregate_log_data` → `synthesize_weekly_summary` →
    `generate_weekly_pdf` → `store_weekly_pdf` → `update_weekly_report`
  - `compensate/4` on `update_weekly_report` calls `:mark_failed` on error

### Oban Workers

- `lib/sitevoice/workers/weekly_report_scheduler_worker.ex` — cron job, runs every Friday at
  5pm UTC (`0 17 * * 5`); no job args; lists all active orgs (global query, no tenant); for each
  org, lists active projects; for each project, creates a `WeeklyReport` record for the current
  week (Mon–Sun) via `:create` action; enqueues `WeeklyReportWorker` with
  `%{report_id: id, organization_id: org_id}`; skips if a report for this week already exists
- `lib/sitevoice/workers/weekly_report_worker.ex` — queue `:reports`, `max_attempts: 3`; args:
  `%{"report_id" => uuid, "organization_id" => uuid}`; sets tenant; marks report `:generating`;
  runs `GenerateWeeklyReport` reactor; on success, enqueues `WeeklyReportNotifyWorker`
- `lib/sitevoice/workers/weekly_report_notify_worker.ex` — queue `:notifications`,
  `max_attempts: 3`; fetches WeeklyReport (with project loaded); fetches PM memberships; fetches
  PDF from Tigris; sends `WeeklyReportEmail.report_ready/3` to each PM

### Email

- `lib/sitevoice/reporting/emails/weekly_report_email.ex` — `Sitevoice.Reporting.Emails.WeeklyReportEmail`
  - `report_ready(report, pdf_binary, pm)` — subject: `"Weekly Report — {project.name} · {week_start} – {week_end}"`; PDF attached; HTML body with summary, accomplishments, issues

### Typst Template

- `priv/typst/weekly_report.typ` — Weekly PDF layout
  - Header: project name, week range, generated date
  - Executive Summary section (Claude narrative)
  - Key Accomplishments (bullet list)
  - Outstanding Issues (bullet list, highlighted)
  - Trends (bullet list)
  - Labor Summary table (aggregated totals by trade)
  - Per-day snapshot table (date, foreman, status, labor headcount)

### LiveView

- `lib/sitevoice_web/live/weekly_reports_live.ex` — route: `/projects/:project_id/weekly-reports`
  - Lists `WeeklyReport` records for the project (status badge: pending/generating/ready/failed)
  - "Generate This Week's Report" button — creates WeeklyReport + enqueues `WeeklyReportWorker`
    immediately; disabled if a report for this week already exists or is generating
  - Subscribes to PubSub `"org:{org_id}:weekly_report:{report_id}"` for status updates
  - "Download PDF" link for reports in `:ready` status
  - LiveView updates report status in real-time as the reactor broadcasts progress

### Tests

- `test/sitevoice/reporting/weekly_report_test.exs` — resource action tests
- `test/sitevoice/workers/weekly_report_worker_test.exs` — Oban worker tests
- `test/sitevoice/workers/weekly_report_scheduler_worker_test.exs` — scheduler logic
- `test/sitevoice/reporting/reactors/generate_weekly_report_test.exs` — integration test
  with Req.Test stubs for Claude and Imprintor

## Existing Files To Modify

- `lib/sitevoice/reporting/reporting.ex` (domain) — add `WeeklyReport` to resources list
- `config/config.exs` — add `{"0 17 * * 5", Sitevoice.Workers.WeeklyReportSchedulerWorker}` to
  Oban cron table and `:reports` to Oban queues
- `lib/sitevoice_web/router.ex` — add route for `WeeklyReportsLive`
- `lib/sitevoice_web/live/projects/show_live.ex` (or equivalent project page) — add "Weekly
  Reports" navigation link

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- `require Ash.Query` wherever `Ash.Query` macros (`filter/2`) are used
- `organization_id` is never accepted from API request bodies — internal actions only
- All Oban job args must include `organization_id`
- Tigris keys: `{organization_id}/weekly-reports/{report_id}.pdf`
- PubSub topics: `"org:{org_id}:weekly_report:{report_id}"` (broadcast from reactor steps)
- Use `Req.Test` stubs for Claude and Imprintor calls in tests — never hit real endpoints
- All tests tagged `@moduletag slice: :weekly_report`
- Claude model: `claude-sonnet-4-20250514` (matches rest of project)
- `mix compile --warnings-as-errors` — zero warnings
