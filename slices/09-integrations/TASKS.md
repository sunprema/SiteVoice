# Tasks — Slice 09: Integrations

Work through in order. Check off each task as it is completed.

---

## 1. Create Integrations Domain

File: `lib/sitevoice/integrations.ex`

- [ ] Define `Sitevoice.Integrations` Ash domain
- [ ] Add `Integration` and `IntegrationEvent` resources

## 2. Create Integration Resource

File: `lib/sitevoice/integrations/integration.ex`

- [ ] Define `Sitevoice.Integrations.Integration` with `use Ash.Resource`
- [ ] Multitenancy: `strategy :attribute; attribute :organization_id`
- [ ] Fields: `provider` (atom enum: `:procore`), `config` (map), `active` (boolean, default: true)
- [ ] Actions: `:read`, `:create`, `:update`, `:destroy`
- [ ] Policies: org members can read; only admins can create/update

## 3. Create IntegrationEvent Resource

File: `lib/sitevoice/integrations/integration_event.ex`

- [ ] Define `Sitevoice.Integrations.IntegrationEvent` with `use Ash.Resource`
- [ ] Multitenancy: `strategy :attribute; attribute :organization_id`
- [ ] Fields: `integration_id` (uuid), `log_id` (uuid), `status` (atom enum: `:pending`, `:sent`, `:failed`), `payload` (map), `response` (map, nullable)
- [ ] Actions: `:read`, `:create`, `:update` (status + response only)
- [ ] Policies: read for org members; create/update for system (authorize?: false in worker)

## 4. Implement DispatchIntegrations Change

File: `lib/sitevoice/reporting/changes/dispatch_integrations.ex`

- [ ] Implement `change/3` with `Ash.Changeset.after_action/2`
- [ ] Inside callback: query `Integration` where `active: true` with `tenant:` + `authorize?: false`
- [ ] For each integration: enqueue `DispatchIntegrationWorker` with `%{log_id: log.id, integration_id: integration.id, organization_id: log.organization_id}`
- [ ] Return `{:ok, log}`

## 5. Create DispatchIntegrationWorker

File: `lib/sitevoice/workers/dispatch_integration_worker.ex`

- [ ] `use Oban.Worker, queue: :integrations, max_attempts: 3`
- [ ] `perform/1`:
  - [ ] Set tenant from `organization_id` arg
  - [ ] Load `Integration` and `DailyLog` (with structured fields)
  - [ ] Build Procore-compatible payload from log fields
  - [ ] POST to Procore API via `Req.post/2` with integration config credentials
  - [ ] Create `IntegrationEvent` with status `:sent` on success, `:failed` on error
  - [ ] Return `:ok` on success; `{:error, reason}` on failure (triggers Oban retry)

## 6. Add Integrations Queue to Oban Config

File: `config/config.exs`

- [ ] Add `integrations: 5` to Oban queues list

## 7. Write Integration Resource Tests

File: `test/sitevoice/integrations/integration_test.exs`

- [ ] Tag `@moduletag slice: :integrations`
- [ ] Test create and read with tenant set
- [ ] Test that organization_id cannot be set via action params

## 8. Write DispatchIntegrationWorker Tests

File: `test/sitevoice/workers/dispatch_integration_worker_test.exs`

- [ ] Tag `@moduletag slice: :integrations`
- [ ] `use Oban.Testing, repo: Sitevoice.Repo`
- [ ] Stub Procore HTTP endpoint with `Req.Test`
- [ ] Test successful dispatch creates `IntegrationEvent` with status `:sent`
- [ ] Test failed HTTP call creates `IntegrationEvent` with status `:failed` and returns `{:error, _}`

## 9. Verify

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:integrations` — all tests pass
- [ ] `mix test` — no regressions in slices 00–08
