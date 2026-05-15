# Slice 09 — Integrations

**Goal:** When a `DailyLog` is approved and submitted, dispatch the structured log data to any
active third-party integrations configured for the org (initially: Procore). Record every
dispatch attempt as an `IntegrationEvent` for audit and retry tracking.

## Acceptance Criteria

- [ ] `Sitevoice.Integrations.Integration` resource exists: tenanted, fields `provider`, `config`, `active`; multitenancy via `organization_id`
- [ ] `Sitevoice.Integrations.IntegrationEvent` resource exists: tenanted, fields `integration_id`, `log_id`, `status`, `payload`, `response`
- [ ] `Sitevoice.Reporting.Changes.DispatchIntegrations` implemented: queries active integrations for org; enqueues one `DispatchIntegrationWorker` job per integration
- [ ] `Sitevoice.Workers.DispatchIntegrationWorker` queue `:integrations`, `max_attempts: 3`; posts log payload to Procore API via `Req`; creates `IntegrationEvent` record with result
- [ ] `DailyLog :approve_and_submit` action already wires `DispatchIntegrations` change (stub exists — implement the body)
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:integrations` — all tests pass
- [ ] `mix test` — no regressions in slices 00–08

## What This Slice Does NOT Include

- Webhook ingestion from Procore
- OAuth flow for Procore (API key only for MVP)
- Integration management UI (admin panel)
- Additional providers beyond Procore
- React Native integration settings screen (Slice 10)
