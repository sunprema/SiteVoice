# Tasks — Slice 09: Integrations

Work through in order. Check off each task as it is completed.

---

## 1. Create Integrations Domain

File: `lib/sitevoice/integrations.ex`

- [x] Define `Sitevoice.Integrations` Ash domain
- [x] Add `Integration` and `IntegrationEvent` resources

## 2. Create Integration Resource

File: `lib/sitevoice/integrations/integration.ex`

- [x] Define `Sitevoice.Integrations.Integration` with `use Ash.Resource`
- [x] Multitenancy: `strategy :attribute; attribute :organization_id`
- [x] Fields: `provider` (atom enum: `:procore`), `config` (map), `active` (boolean, default: true)
- [x] Actions: `:read`, `:create`, `:update`, `:destroy`
- [x] Policies: org members can read; only admins can create/update

## 3. Create IntegrationEvent Resource

File: `lib/sitevoice/integrations/integration_event.ex`

- [x] Define `Sitevoice.Integrations.IntegrationEvent` with `use Ash.Resource`
- [x] Multitenancy: `strategy :attribute; attribute :organization_id`
- [x] Fields: `integration_id` (uuid), `log_id` (uuid), `status` (atom enum: `:pending`, `:sent`, `:failed`), `payload` (map), `response` (map, nullable)
- [x] Actions: `:read`, `:create`, `:update` (status + response only)
- [x] Policies: read for org members; create/update for system (authorize?: false in worker)

## 4. Implement DispatchIntegrations Change

File: `lib/sitevoice/reporting/changes/dispatch_integrations.ex`

- [x] Implement `change/3` with `Ash.Changeset.after_action/2`
- [x] Inside callback: query `Integration` where `active: true` with `tenant:` + `authorize?: false`
- [x] For each integration: enqueue `DispatchIntegrationWorker` with `%{log_id: log.id, integration_id: integration.id, organization_id: log.organization_id}`
- [x] Return `{:ok, log}`

## 5. Create DispatchIntegrationWorker

File: `lib/sitevoice/workers/dispatch_integration_worker.ex`

- [x] `use Oban.Worker, queue: :integrations, max_attempts: 3`
- [x] `perform/1`:
  - [x] Set tenant from `organization_id` arg
  - [x] Load `Integration` and `DailyLog` (with structured fields)
  - [x] Build Procore-compatible payload from log fields
  - [x] POST to Procore API via `Req.post/2` with integration config credentials
  - [x] Create `IntegrationEvent` with status `:sent` on success, `:failed` on error
  - [x] Return `:ok` on success; `{:error, reason}` on failure (triggers Oban retry)

## 6. Add Integrations Queue to Oban Config

File: `config/config.exs`

- [x] Add `integrations: 5` to Oban queues list (already present as `integrations: 10`)

## 7. Write Integration Resource Tests

File: `test/sitevoice/integrations/integration_test.exs`

- [x] Tag `@moduletag slice: :integrations`
- [x] Test create and read with tenant set
- [x] Test that organization_id cannot be set via action params

## 8. Write DispatchIntegrationWorker Tests

File: `test/sitevoice/workers/dispatch_integration_worker_test.exs`

- [x] Tag `@moduletag slice: :integrations`
- [x] `use Oban.Testing, repo: Sitevoice.Repo`
- [x] Stub Procore HTTP endpoint with `Req.Test`
- [x] Test successful dispatch creates `IntegrationEvent` with status `:sent`
- [x] Test failed HTTP call creates `IntegrationEvent` with status `:failed` and returns `{:error, _}`

## 9. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:integrations` — all tests pass
- [x] `mix test` — no regressions in slices 00–08
