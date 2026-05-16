# Tasks — Slice 12: Weekly Report

Work through in order. Check off each task as it is completed.

---

## 1. Create WeeklyReport Ash Resource

File: `lib/sitevoice/reporting/weekly_report.ex`

- [x] Define `Sitevoice.Reporting.WeeklyReport` with `use Ash.Resource`
- [x] Add multitenancy block: `strategy :attribute`, `attribute :organization_id`
- [x] Add postgres block with table `"weekly_reports"` and `repo Sitevoice.Repo`
- [x] Add custom index on `[:organization_id, :project_id, :week_start]`
- [x] Define attributes:
  - [x] `uuid_primary_key :id`
  - [x] `organization_id` (uuid, allow_nil?: false, public?: false)
  - [x] `week_start` (date, allow_nil?: false)
  - [x] `week_end` (date, allow_nil?: false)
  - [x] `status` (atom, constraints: `[one_of: [:pending, :generating, :ready, :failed]]`, default `:pending`)
  - [x] `summary` (string)
  - [x] `key_accomplishments` ({:array, :string}, default [])
  - [x] `outstanding_issues` ({:array, :string}, default [])
  - [x] `trends` ({:array, :map}, default [])
  - [x] `total_labor_hours` (float)
  - [x] `total_headcount_days` (integer)
  - [x] `daily_log_count` (integer)
  - [x] `pdf_key` (string)
  - [x] `generated_at` (utc_datetime)
  - [x] `timestamps()`
- [x] Add identity `unique_report_per_week` on `[:organization_id, :project_id, :week_start]`
- [x] Add relationships: `belongs_to :organization`, `belongs_to :project`
- [x] Add calculation `pdf_url` using `Sitevoice.Reporting.Calculations.WeeklyPdfUrl`
- [x] Define actions:
  - [x] `:create` — `accept [:week_start, :week_end, :project_id]`; `change set_attribute(:organization_id, arg(:organization_id))` via argument
  - [x] `:mark_generating` — update, `change set_attribute(:status, :generating)`
  - [x] `:mark_ready` — update, accept summary fields + pdf_key + totals + generated_at
  - [x] `:mark_failed` — update, `change set_attribute(:status, :failed)`
  - [x] `:read` — primary read
  - [x] `:list_for_project` — filter by `project_id`, sort by `week_start: :desc`
  - [x] `:get_by_week` — filter by `project_id` + `week_start`, `get? true`
- [x] Define policies:
  - [x] Mutations (`:create`, `:mark_generating`, `:mark_ready`, `:mark_failed`): `authorize_if actor_absent()` and `authorize_if actor_attribute_equals(:role, :org_admin)`
  - [x] Reads: `authorize_if actor_attribute_equals(:role, :pm)`, `:owner`, `:org_admin`

## 2. Create WeeklyPdfUrl Calculation

File: `lib/sitevoice/reporting/calculations/weekly_pdf_url.ex`

- [x] Define `Sitevoice.Reporting.Calculations.WeeklyPdfUrl` with `use Ash.Resource.Calculation`
- [x] Implement `calculate/3` — when `pdf_key` is nil return nil; otherwise call
      `Sitevoice.Storage.presigned_url(pdf_key)` (same pattern as `PdfUrl` calculation)

## 3. Register Resource in Domain

File: `lib/sitevoice/reporting/reporting.ex`

- [x] Add `resource Sitevoice.Reporting.WeeklyReport` to the domain resources list

## 4. Generate and Run Migration

- [x] Run `mix ash.codegen weekly_report` to generate migration
- [x] Review generated migration for correctness (table name, index, identity)
- [x] Run `mix ash.migrate` to apply migration

## 5. Create FetchWeeklyLogs Step

File: `lib/sitevoice/reporting/steps/fetch_weekly_logs.ex`

- [x] Define `Sitevoice.Reporting.Steps.FetchWeeklyLogs` with `use Reactor.Step`
- [x] Implement `run/3`:
  - [x] Extract `report`, `organization_id` from arguments
  - [x] Call `Sitevoice.Reporting.DailyLog` `:list_for_date_range` with `project_id: report.project_id`, `from: report.week_start`, `to: report.week_end`, `tenant: organization_id`, `authorize?: false`
  - [x] Filter result to only `status == :submitted` logs
  - [x] Load associations: `[:foreman, :project]`
  - [x] Return `{:ok, submitted_logs}`
- [x] Implement `compensate/4` — no side effects, return `:ok`

## 6. Create AggregateLogData Step

File: `lib/sitevoice/reporting/steps/aggregate_log_data.ex`

- [x] Define `Sitevoice.Reporting.Steps.AggregateLogData` with `use Reactor.Step`
- [x] Implement `run/3` — pure Elixir, no I/O:
  - [x] Sum `total_labor_hours` across all logs (`Enum.reduce` over `labor` arrays, summing `hours`)
  - [x] Sum `total_headcount_days` (headcount × 1 per log entry)
  - [x] Flatten `progress`, `equipment`, `materials`, `delays`, `safety` across all logs
  - [x] Collect unique non-nil `weather` strings
  - [x] Return `{:ok, %{logs: logs, total_labor_hours: float, total_headcount_days: integer, progress: [...], equipment: [...], materials: [...], delays: [...], safety: [...], weather: [...], daily_log_count: integer}}`
- [x] Implement `compensate/4` — return `:ok`

## 7. Create SynthesizeWeeklySummary Step

File: `lib/sitevoice/reporting/steps/synthesize_weekly_summary.ex`

- [x] Define `Sitevoice.Reporting.Steps.SynthesizeWeeklySummary` with `use Reactor.Step`
- [x] Implement `run/3`:
  - [x] Build structured prompt from aggregated data (see SLICE.md Key Behaviours)
  - [x] Call Claude API via `Req.post!/2` with `timeout: 30_000`
  - [x] Model: `claude-sonnet-4-20250514`, `max_tokens: 1500`
  - [x] Parse JSON response body — extract `summary`, `key_accomplishments`, `outstanding_issues`, `trends`
  - [x] Return `{:ok, %{summary: ..., key_accomplishments: [...], outstanding_issues: [...], trends: [...]}}`
  - [x] Return `{:error, reason}` on API error or JSON parse failure
- [x] Implement `compensate/4` — return `:ok`

## 8. Create GenerateWeeklyPdf Step

File: `lib/sitevoice/reporting/steps/generate_weekly_pdf.ex`

- [x] Define `Sitevoice.Reporting.Steps.GenerateWeeklyPdf` with `use Reactor.Step`
- [x] Implement `run/3`:
  - [x] Load `priv/typst/weekly_report.typ` template
  - [x] Merge aggregated data + Claude output into template variables map
  - [x] Call Imprintor to render PDF (same pattern as `generate_pdf.ex`)
  - [x] Return `{:ok, pdf_binary}`
- [x] Implement `compensate/4` — return `:ok`

## 9. Create StoreWeeklyPdf Step

File: `lib/sitevoice/reporting/steps/store_weekly_pdf.ex`

- [x] Define `Sitevoice.Reporting.Steps.StoreWeeklyPdf` with `use Reactor.Step`
- [x] Implement `run/3`:
  - [x] Build Tigris key: `"#{organization_id}/weekly-reports/#{report_id}.pdf"`
  - [x] Upload via `Sitevoice.Storage.upload(key, pdf_binary, "application/pdf")`
  - [x] Return `{:ok, tigris_key}`
- [x] Implement `compensate/4`:
  - [x] On compensation: call `Sitevoice.Storage.delete(tigris_key)` to clean up partial upload
  - [x] Return `:ok`

## 10. Create UpdateWeeklyReport Step

File: `lib/sitevoice/reporting/steps/update_weekly_report.ex`

- [x] Define `Sitevoice.Reporting.Steps.UpdateWeeklyReport` with `use Reactor.Step`
- [x] Implement `run/3`:
  - [x] Call `WeeklyReport` `:mark_ready` action with all fields: `summary`, `key_accomplishments`,
        `outstanding_issues`, `trends`, `pdf_key`, `total_labor_hours`, `total_headcount_days`,
        `daily_log_count`, `generated_at: DateTime.utc_now()`
  - [x] Broadcast `{:weekly_report_status, %{report_id: id, status: :ready}}` to
        `"org:{org_id}:weekly_report:{report_id}"` PubSub topic
  - [x] Return `{:ok, updated_report}`
- [x] Implement `compensate/4`:
  - [x] Call `WeeklyReport` `:mark_failed` action
  - [x] Broadcast `{:weekly_report_status, %{report_id: id, status: :failed}}`
  - [x] Return `:ok`

## 11. Create GenerateWeeklyReport Reactor

File: `lib/sitevoice/reporting/reactors/generate_weekly_report.ex`

- [x] Define `Sitevoice.Reporting.Reactors.GenerateWeeklyReport` with `use Reactor`
- [x] Declare inputs: `report_id`, `organization_id`
- [x] Wire steps in dependency order:
  - [x] `set_tenant` (`Sitevoice.Reporting.Steps.SetTenant`) — first step
  - [x] `fetch_report` — fetch `WeeklyReport` by `report_id` (tenant: org_id), wait_for set_tenant
  - [x] `fetch_weekly_logs` (`FetchWeeklyLogs`) — wait_for fetch_report
  - [x] `aggregate_log_data` (`AggregateLogData`) — wait_for fetch_weekly_logs
  - [x] `synthesize_weekly_summary` (`SynthesizeWeeklySummary`) — wait_for aggregate_log_data
  - [x] `generate_weekly_pdf` (`GenerateWeeklyPdf`) — wait_for synthesize_weekly_summary + aggregate_log_data
  - [x] `store_weekly_pdf` (`StoreWeeklyPdf`) — wait_for generate_weekly_pdf
  - [x] `update_weekly_report` (`UpdateWeeklyReport`) — wait_for store_weekly_pdf + synthesize_weekly_summary + aggregate_log_data

## 12. Create Typst Template

File: `priv/typst/weekly_report.typ`

- [x] Define page layout (A4, margins matching daily_log.typ)
- [x] Header block: SiteVoice branding, project name, week range, organization
- [x] Section: Executive Summary (Claude narrative text)
- [x] Section: Key Accomplishments (green-accented bullet list)
- [x] Section: Outstanding Issues (red-accented bullet list, only if non-empty)
- [x] Section: Trends (orange-accented bullet list with severity badges)
- [x] Section: Labor Summary table (trade, headcount, hours)
- [x] Section: Daily Snapshot table (date, foreman name, headcount, status pill)
- [x] Footer with page number and generation date

## 13. Create WeeklyReportWorker

File: `lib/sitevoice/workers/weekly_report_worker.ex`

- [x] Define `Sitevoice.Workers.WeeklyReportWorker` with `use Oban.Worker, queue: :reports, max_attempts: 3`
- [x] Implement `perform/1`:
  - [x] Extract `report_id`, `organization_id` from job args
  - [x] Set tenant: `Ash.set_tenant(organization_id)`
  - [x] Call `WeeklyReport :mark_generating` (tenant: org_id, authorize?: false)
  - [x] Run `GenerateWeeklyReport` reactor with `%{report_id: report_id, organization_id: organization_id}`
  - [x] On `{:ok, _}`: enqueue `WeeklyReportNotifyWorker` with `%{report_id: report_id, organization_id: organization_id}`; return `:ok`
  - [x] On `{:error, reason}`: return `{:error, reason}` so Oban retries

## 14. Create WeeklyReportSchedulerWorker

File: `lib/sitevoice/workers/weekly_report_scheduler_worker.ex`

- [x] Define `Sitevoice.Workers.WeeklyReportSchedulerWorker` with `use Oban.Worker, queue: :reports, max_attempts: 3`
- [x] Implement `current_week/0` helper — returns `{week_start, week_end}` using ISO week Monday
- [x] Implement `perform/1`:
  - [x] `require Ash.Query`
  - [x] List all active `Organization` records (global, no tenant, authorize?: false)
  - [x] For each org:
    - [x] Set tenant to org.id
    - [x] List active `Project` records (authorize?: false)
    - [x] For each project:
      - [x] Compute `{week_start, week_end}`
      - [x] Call `WeeklyReport :get_by_week` — if `{:ok, nil}` (no existing report)
      - [x] Call `WeeklyReport :create` with `%{project_id: project.id, week_start: week_start, week_end: week_end, organization_id: org.id}` (authorize?: false)
      - [x] Enqueue `WeeklyReportWorker` with `%{report_id: report.id, organization_id: org.id}`
      - [x] If report already exists, skip silently
  - [x] Return `:ok`

## 15. Create WeeklyReportNotifyWorker

File: `lib/sitevoice/workers/weekly_report_notify_worker.ex`

- [x] Define `Sitevoice.Workers.WeeklyReportNotifyWorker` with `use Oban.Worker, queue: :notifications, max_attempts: 3`
- [x] Implement `perform/1`:
  - [x] Extract `report_id`, `organization_id`
  - [x] Set tenant
  - [x] Load `WeeklyReport` with `[:project, :organization]` (authorize?: false)
  - [x] Guard: if `report.pdf_key` is nil, return `{:error, :no_pdf}`
  - [x] Load PM memberships for the project (role: :pm)
  - [x] Load User records for each PM membership
  - [x] Fetch PDF binary from Tigris using `report.pdf_key`
  - [x] For each PM: build and deliver `WeeklyReportEmail.report_ready/3`
  - [x] Return `:ok`

## 16. Create WeeklyReportEmail

File: `lib/sitevoice/reporting/emails/weekly_report_email.ex`

- [x] Define `Sitevoice.Reporting.Emails.WeeklyReportEmail`
- [x] `import Swoosh.Email`
- [x] Implement `report_ready(report, pdf_binary, pm)`:
  - [x] `to: {pm.name, to_string(pm.email)}`
  - [x] `from: {"SiteVoice", "reports@sitevoice.app"}`
  - [x] `subject: "Weekly Report — #{report.project.name} · #{report.week_start} – #{report.week_end}"`
  - [x] HTML body: summary paragraph, accomplishments list, outstanding issues list
  - [x] Plain text fallback body
  - [x] PDF attachment: `"weekly-report-#{report.week_start}.pdf"`, content type `application/pdf`

## 17. Update Oban Config

File: `config/config.exs`

- [x] Add `reports: 5` to Oban queues map
- [x] Add `{"0 17 * * 5", Sitevoice.Workers.WeeklyReportSchedulerWorker}` to cron table

## 18. Create WeeklyReportsLive

File: `lib/sitevoice_web/live/weekly_reports_live.ex`

- [x] Define `SitevoiceWeb.WeeklyReportsLive` with `use SitevoiceWeb, :live_view`
- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`:
  - [x] Extract `project_id` from params
  - [x] Load project (authorize? true)
  - [x] Load weekly reports via `WeeklyReport :list_for_project`
  - [x] Compute `{current_week_start, _}` and check if a report for this week already exists
  - [x] Assign `:project`, `:reports`, `:current_week_start`, `:generating?`
- [x] `handle_event("generate_report", ...)`:
  - [x] Guard: return noop if report for this week already exists
  - [x] Create `WeeklyReport` via `:create` action
  - [x] Enqueue `WeeklyReportWorker`
  - [x] Subscribe to PubSub topic for this report
  - [x] Show toast: "Generating weekly report…"
  - [x] Update `:reports` list and set `:generating?` to true
- [x] `handle_info({:weekly_report_status, payload}, socket)`:
  - [x] Find report in list by `report_id`; update its status in assigns
  - [x] If status `:ready`: set `:generating?` false, show toast "Weekly report ready"
  - [x] If status `:failed`: set `:generating?` false, show error toast
- [x] Render table of reports with columns: week range, status badge, log count,
      labor hours, "Download PDF" link
- [x] Render "Generate This Week's Report" button (disabled when generating or report exists)

## 19. Add Route

File: `lib/sitevoice_web/router.ex`

- [x] Add `live "/projects/:project_id/weekly-reports", WeeklyReportsLive` inside authenticated
      scope

## 20. Add Navigation Link

File: project detail LiveView (e.g., `lib/sitevoice_web/live/projects/show_live.ex`)

- [x] Add "Weekly Reports" navigation link pointing to `/projects/{id}/weekly-reports`

## 21. Write Tests

### Resource Tests

File: `test/sitevoice/reporting/weekly_report_test.exs`

- [x] Tag `@moduletag slice: :weekly_report`
- [x] Test `:create` action creates record with status `:pending`
- [x] Test identity prevents duplicate report for same project + week_start
- [x] Test `:mark_ready` updates all output fields
- [x] Test read policy: PM can read, foreman cannot

### Worker Tests

File: `test/sitevoice/workers/weekly_report_worker_test.exs`

- [x] Tag `@moduletag slice: :weekly_report`
- [x] `use Oban.Testing, repo: Sitevoice.Repo`
- [x] Test `perform/1` runs reactor and enqueues notify worker on success
- [x] Test `perform/1` returns `{:error, reason}` when reactor fails
- [x] Use `Req.Test` stubs for Claude and Imprintor

File: `test/sitevoice/workers/weekly_report_scheduler_worker_test.exs`

- [x] Tag `@moduletag slice: :weekly_report`
- [x] Test scheduler creates WeeklyReport and enqueues WeeklyReportWorker for each org/project
- [x] Test scheduler skips when a report for this week already exists

### Reactor Integration Test

File: `test/sitevoice/reporting/reactors/generate_weekly_report_test.exs`

- [x] Tag `@moduletag slice: :weekly_report`
- [x] Set up org, project, 3 submitted DailyLog fixtures for the current week
- [x] Stub Claude API via `Req.Test` to return valid JSON summary
- [x] Stub Imprintor via `Req.Test` to return a PDF binary
- [x] Stub Tigris upload/fetch via `Req.Test`
- [x] Run reactor; assert `WeeklyReport` transitions to status `:ready`
- [x] Assert `pdf_key` is set and `summary` is not nil

## 22. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:weekly_report` — all tests pass
- [x] `mix test` — no regressions in slices 00–11
