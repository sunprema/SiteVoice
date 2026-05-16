# Slice 12 — Weekly Report

**Goal:** Generate a weekly summary PDF for each project, synthesized by Claude from the week's
submitted daily logs. Reports are generated automatically every Friday at 5pm UTC and can also be
triggered on demand from the LiveView project page. PMs receive the summary PDF by email when the
report is ready.

## Acceptance Criteria

### WeeklyReport Resource

- [ ] `Sitevoice.Reporting.WeeklyReport` exists with multitenancy (`strategy :attribute`,
      `attribute :organization_id`)
- [ ] Attributes: `week_start` (date, Monday), `week_end` (date, Sunday), `status`
      (atom: `pending | generating | ready | failed`, default `:pending`), `summary` (string),
      `key_accomplishments` ({:array, :string}), `outstanding_issues` ({:array, :string}),
      `trends` ({:array, :map}), `total_labor_hours` (float), `total_headcount_days` (integer),
      `daily_log_count` (integer), `pdf_key` (string), `generated_at` (utc_datetime)
- [ ] Belongs_to relationships: `organization`, `project`
- [ ] Identity `unique_report_per_week` on `[:organization_id, :project_id, :week_start]`
- [ ] Actions: `:create` (internal), `:mark_generating`, `:mark_ready` (accepts all output
      fields), `:mark_failed`, `:read` (primary), `:list_for_project` (filter by project_id,
      sort week_start desc), `:get_by_week` (filter project_id + week_start, get? true)
- [ ] Calculation `pdf_url` that generates a presigned Tigris URL from `pdf_key` (mirrors
      `Sitevoice.Reporting.Calculations.PdfUrl`)
- [ ] Policies: `actor_absent()` and `org_admin` authorize mutations; `:pm`, `:owner`,
      `:org_admin` authorize reads
- [ ] Resource registered in `Sitevoice.Reporting` domain
- [ ] Migration generated via `mix ash.codegen` and applied

### Reactor Steps

- [ ] `Sitevoice.Reporting.Steps.FetchWeeklyLogs` — calls `DailyLog.list_for_date_range` with
      `tenant: org_id, authorize?: false`; returns only logs where `status == :submitted`
- [ ] `Sitevoice.Reporting.Steps.AggregateLogData` — pure step (no external I/O); sums
      `labor` headcount and hours across all logs; flattens `progress`, `equipment`, `materials`,
      `delays`, `safety` lists; collects unique `weather` values; returns structured map
- [ ] `Sitevoice.Reporting.Steps.SynthesizeWeeklySummary` — builds a structured prompt from the
      aggregated data map; calls Claude `claude-sonnet-4-20250514` with a `max_tokens: 1500`
      limit and `timeout: 30_000`; parses JSON response into `%{summary:, key_accomplishments:,
      outstanding_issues:, trends:}`; implements `compensate/4`
- [ ] `Sitevoice.Reporting.Steps.GenerateWeeklyPdf` — calls Imprintor with
      `priv/typst/weekly_report.typ`; passes all aggregated and synthesized data as template
      variables; returns PDF binary; implements `compensate/4`
- [ ] `Sitevoice.Reporting.Steps.StoreWeeklyPdf` — uploads PDF to Tigris under
      `{org_id}/weekly-reports/{report_id}.pdf`; returns Tigris key; implements `compensate/4`
      (deletes uploaded object on failure)
- [ ] `Sitevoice.Reporting.Steps.UpdateWeeklyReport` — updates `WeeklyReport` to status `:ready`
      with all output fields and `generated_at: DateTime.utc_now()`; implements `compensate/4`
      that calls `:mark_failed`

### Reactor

- [ ] `Sitevoice.Reporting.Reactors.GenerateWeeklyReport` exists with inputs `report_id` and
      `organization_id`
- [ ] Step order: `set_tenant` → `fetch_report` → `fetch_weekly_logs` → `aggregate_log_data` →
      `synthesize_weekly_summary` → `generate_weekly_pdf` → `store_weekly_pdf` →
      `update_weekly_report`
- [ ] Each step has `wait_for` wiring on its dependencies
- [ ] Steps that call external APIs have explicit timeouts
- [ ] On any step failure, `compensate/4` on `update_weekly_report` marks the report `:failed`

### Oban Workers

- [ ] `Sitevoice.Workers.WeeklyReportSchedulerWorker` — queue `:reports`, `max_attempts: 3`;
      `perform/1` lists all active orgs (global); for each org + active project, computes
      current week's `week_start` (Monday) and `week_end` (Sunday); calls `:get_by_week`; if
      no existing report, calls `:create` then enqueues `WeeklyReportWorker`; skips quietly if
      report already exists
- [ ] `Sitevoice.Workers.WeeklyReportWorker` — queue `:reports`, `max_attempts: 3`; args:
      `%{"report_id" => uuid, "organization_id" => uuid}`; sets tenant; calls `:mark_generating`;
      runs `GenerateWeeklyReport` reactor; on success enqueues `WeeklyReportNotifyWorker`
- [ ] `Sitevoice.Workers.WeeklyReportNotifyWorker` — queue `:notifications`, `max_attempts: 3`;
      fetches `WeeklyReport` (with project loaded); fetches PM memberships; fetches PDF binary
      from Tigris; sends `WeeklyReportEmail.report_ready/3` to each PM; returns
      `{:error, :no_pdf}` (triggers retry) if `pdf_key` is nil

### Cron

- [ ] `config/config.exs` Oban cron table includes
      `{"0 17 * * 5", Sitevoice.Workers.WeeklyReportSchedulerWorker}`
- [ ] `config/config.exs` Oban queues include `reports: 5`

### Email

- [ ] `Sitevoice.Reporting.Emails.WeeklyReportEmail.report_ready/3` builds a Swoosh email with:
      - `to: {pm.name, pm.email}`
      - `from: {"SiteVoice", "reports@sitevoice.app"}`
      - `subject: "Weekly Report — {project.name} · {week_start} – {week_end}"`
      - HTML body with summary paragraph, accomplishments, outstanding issues
      - PDF attached as `weekly-report-{week_start}.pdf`, content type `application/pdf`

### Typst Template

- [ ] `priv/typst/weekly_report.typ` renders a multi-section PDF:
      - Header: project name, week range, organization name
      - Executive Summary (Claude narrative)
      - Key Accomplishments (styled bullet list, green accent)
      - Outstanding Issues (styled bullet list, red accent)
      - Trends (styled bullet list, orange accent)
      - Labor Summary table (trade, total headcount, total hours)
      - Per-day snapshot table (date, foreman, headcount, status)

### LiveView

- [ ] `SitevoiceWeb.WeeklyReportsLive` at route `/projects/:project_id/weekly-reports`
- [ ] Mounts with project + list of `WeeklyReport` records for the project (descending)
- [ ] Each row shows: week range, status badge, daily_log_count, total_labor_hours, "Download
      PDF" link (only when status `:ready`)
- [ ] "Generate This Week's Report" button:
      - Disabled when a report for the current ISO week already exists with status
        `:pending | :generating | :ready`
      - On click: calls `:create` then enqueues `WeeklyReportWorker`; shows toast
- [ ] Subscribes to `"org:{org_id}:weekly_report:{report_id}"` via PubSub; updates the row
      status live as the reactor progresses
- [ ] Navigation link to weekly reports added to project detail page

### Verification

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:weekly_report` — all tests pass
- [ ] `mix test` — no regressions in slices 00–11

## What This Slice Does NOT Include

- Per-foreman weekly summaries (project-level only)
- Cross-project roll-up report (single email covering all projects — post-MVP)
- Slack / Teams delivery
- Configurable cron schedule per organization
- Archive or deletion of old weekly reports
- Mobile screen for weekly reports (Slice 10 scope)

## Key Behaviours

### Claude Prompt Structure

Send aggregated structured data (not raw transcripts) to reduce token usage:

```
You are a construction project reporting assistant. Analyze the following week of site activity
and produce a JSON response with these keys:
- "summary": 2–3 paragraph executive narrative (string)
- "key_accomplishments": list of strings (max 8)
- "outstanding_issues": list of strings (max 5)
- "trends": list of objects {description: string, severity: "low"|"medium"|"high"}

Week: {week_start} to {week_end}
Project: {project_name}
Days with submitted logs: {count} of 5

AGGREGATED DATA:
Progress items: [...]
Labor summary: [...]
Equipment used: [...]
Materials: [...]
Delays: [...]
Safety observations: [...]
Weather: [...]

Respond ONLY with valid JSON. No markdown.
```

### Week Calculation

```elixir
# Always Monday–Sunday of the ISO week containing today
def current_week do
  today = Date.utc_today()
  dow = Date.day_of_week(today)          # 1=Mon … 7=Sun
  week_start = Date.add(today, 1 - dow)
  week_end = Date.add(week_start, 6)
  {week_start, week_end}
end
```

### WeeklyReportWorker Flow

```
perform(%{report_id, organization_id})
  → set_tenant(org_id)
  → load WeeklyReport
  → mark_generating
  → run GenerateWeeklyReport reactor
  → on {:ok, _} → enqueue WeeklyReportNotifyWorker
  → on {:error, _} → return {:error, reason} (Oban retries)
```

### Tenant Rules

- All Ash calls in workers: `tenant: org_id, authorize?: false`
- Scheduler worker iterates orgs globally then switches tenant per org
- Reactor: `SetTenant` step runs first; all subsequent Ash steps `wait_for: [:set_tenant]`

### PubSub Broadcasts

Broadcast from reactor steps on status changes:

```elixir
Phoenix.PubSub.broadcast(
  Sitevoice.PubSub,
  "org:#{org_id}:weekly_report:#{report_id}",
  {:weekly_report_status, %{report_id: report_id, status: :ready}}
)
```
