# Context — Slice 09: Integrations

## Dependency

Slice 08 (LiveView Screens) must be complete before starting this slice.

## Purpose

This slice adds the Procore integration adapter. When a `DailyLog` is approved and submitted,
SiteVoice dispatches the structured log data to Procore (if an integration is configured for the org).
All integration events are recorded for audit purposes.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §16 — Integrations: `Integration` resource, `IntegrationEvent` resource, Procore adapter
2. `docs/APPLICATION_SPEC.md` §5.3 — `DailyLog :approve_and_submit` action and post-submission dispatch
3. `docs/CODING_STANDARDS.md` — Ash resource conventions, Oban worker conventions
4. `CLAUDE.md` — Architecture Rules §Multitenancy, §Oban, §Reactor

## Existing State

- `lib/sitevoice/reporting/changes/dispatch_integrations.ex` — stub change exists; needs implementation
- `lib/sitevoice/reporting/daily_log.ex` — `:approve_and_submit` action; `dispatch_integrations` change stub already wired
- `lib/sitevoice/workers/` — Oban worker directory

## New Files To Create

### Ash Resources

- `lib/sitevoice/integrations/integration.ex` — tenanted resource; fields: `provider` (`:procore`), `config` (map), `active` (boolean)
- `lib/sitevoice/integrations/integration_event.ex` — tenanted resource; fields: `integration_id`, `log_id`, `status` (`:pending`, `:sent`, `:failed`), `payload` (map), `response` (map)
- `lib/sitevoice/integrations.ex` — Ash domain

### Oban Worker

- `lib/sitevoice/workers/dispatch_integration_worker.ex` — queue: `:integrations`, `max_attempts: 3`; posts log data to Procore API; records `IntegrationEvent`

### Ash Change

- `lib/sitevoice/reporting/changes/dispatch_integrations.ex` — implement: query active integrations for org, enqueue `DispatchIntegrationWorker` per integration

### Tests

- `test/sitevoice/integrations/integration_test.exs`
- `test/sitevoice/workers/dispatch_integration_worker_test.exs`

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- All integration config (API keys) stored in the `Integration.config` map field, never hardcoded
- Procore HTTP calls use `Req` — stub with `Req.Test` in tests
- All tests tagged `@moduletag slice: :integrations`
- `mix compile --warnings-as-errors` — zero warnings
