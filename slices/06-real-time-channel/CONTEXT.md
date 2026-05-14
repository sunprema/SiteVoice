# Context — Slice 06: Real-time Channels

## Dependency

Slice 05 (PDF Generation) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §11 — Real-time Communication (RecordingChannel, client events table)
2. `docs/APPLICATION_SPEC.md` §6.7 — Phoenix Channels: tenant propagation rules (join + handle_in)
3. `docs/APPLICATION_SPEC.md` §6.8 — PubSub: org-namespaced topics (never bare topics)
4. `docs/APPLICATION_SPEC.md` §9.3 — Ash Reactor: full pipeline definition (where to insert broadcast steps)
5. `docs/CODING_STANDARDS.md` — Reactor step conventions (one file per step, compensate/4)
6. `CLAUDE.md` — Architecture Rules §Multitenancy, §Reactor

## Existing Files To Modify

- `lib/sitevoice_web/channels/recording_channel.ex` — complete the scaffold:
  - Add `Ash.Query.set_tenant(org_id)` call on `join/3` (currently missing)
  - Subscribe to `"org:#{org_id}:log:#{log_id}"` PubSub topic on join so server-side broadcasts reach the client
  - Add `handle_info/2` for `{:report_ready, _}`, `{:pipeline_update, _}`, `{:pipeline_failed, _}` — push each to client
  - Keep existing `handle_in("recording_complete", ...)` unchanged
- `lib/sitevoice_web/channels/user_socket.ex` — register `channel "log:*", SitevoiceWeb.LogChannel`
- `lib/sitevoice/reporting/reactors/process_recording.ex` — insert `broadcast_pipeline_step` calls after `:save_transcript`, `:save_structure`, and `:generate_pdf` steps to emit `pipeline_update` events
- `lib/sitevoice/reporting/steps/broadcast_ready.ex` — confirm it broadcasts on `"org:#{org_id}:log:#{log_id}"` (already correct; verify only)

## New Files To Create

### Channel

- `lib/sitevoice_web/channels/log_channel.ex` — PM dashboard channel
  - Joins on topic `"log:#{log_id}"` (validates against org_id from JWT)
  - Sets tenant on join; subscribes to `"org:#{org_id}:log:#{log_id}"` PubSub topic
  - `handle_info/2` relays `{:report_ready, _}`, `{:pipeline_update, _}`, `{:pipeline_failed, _}` to client

### Reactor step

- `lib/sitevoice/reporting/steps/broadcast_pipeline_step.ex` — broadcasts `pipeline_update` event
  - Matches `%{step: step_name, organization_id: org_id, log_id: log_id}`
  - Publishes `{:pipeline_update, %{step: step_name, status: :complete}}` to `"org:#{org_id}:log:#{log_id}"`
  - `compensate/4` returns `:ok`

### Tests

- `test/sitevoice_web/channels/recording_channel_test.exs`
- `test/sitevoice_web/channels/log_channel_test.exs`
- `test/sitevoice/reporting/steps/broadcast_pipeline_step_test.exs`

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- All PubSub topics must be `"org:#{org_id}:log:#{log_id}"` — never bare
- `Ash.Query.set_tenant/1` must be called on `join/3` AND re-called in every `handle_in/3`
- `handle_info/2` is a Channel callback — no need to re-set tenant (no Ash calls inside)
- Subscribe to PubSub inside `join/3` with `Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)`
- `BroadcastPipelineStep` inserts between key Reactor steps; it must receive `step:` as a string argument so different broadcast steps can label their position in the pipeline
- Reactor step order for broadcasts: after `:save_transcript` (step `"transcribed"`), after `:save_structure` (step `"structured"`), after `:generate_pdf` (step `"pdf_generated"`)
- `LogChannel` join must authorize: the joining user's org_id (from JWT) must match the log's `organization_id`. Fetch the log with `tenant: org_id, authorize?: false` same as `RecordingChannel`
- All tests tagged `@moduletag slice: :realtime`
- Channel tests use `Phoenix.ChannelTest` (`use SitevoiceWeb.ChannelCase`)
- No real PubSub in unit tests — assert `push/3` calls or use `assert_push`
- `mix compile --warnings-as-errors` — zero warnings
