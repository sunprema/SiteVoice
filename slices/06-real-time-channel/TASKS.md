# Tasks — Slice 06: Real-time Channels

Work through in order. Check off each task as it is completed.

---

## 1. Complete RecordingChannel

File: `lib/sitevoice_web/channels/recording_channel.ex`

- [x] Set `Ash.Query.set_tenant(org_id)` as the first line of `join/3` (before `authorized?/2` call)
- [x] Subscribe to `"org:#{org_id}:log:#{log_id}"` via `Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)` inside `join/3` after authorization passes
- [x] Add `handle_info({:report_ready, payload}, socket)` — push `"report_ready"` to client with `payload`
- [x] Add `handle_info({:pipeline_update, payload}, socket)` — push `"pipeline_update"` to client with `payload`
- [x] Add `handle_info({:pipeline_failed, payload}, socket)` — push `"pipeline_failed"` to client with `payload`
- [x] Verify `handle_in("recording_complete", ...)` still re-applies tenant via `Ash.Query.set_tenant(socket.assigns.organization_id)` at the top

## 2. Create LogChannel

File: `lib/sitevoice_web/channels/log_channel.ex`

- [x] Define `SitevoiceWeb.LogChannel` with `use Phoenix.Channel`
- [x] Implement `join("log:" <> log_id, _params, socket)`:
  - [x] Extract `org_id` from `socket.assigns.current_user.organization_id`
  - [x] Call `Ash.Query.set_tenant(org_id)`
  - [x] Fetch log with `Ash.get(DailyLog, log_id, tenant: to_string(org_id), authorize?: false)` — reject join with `{:error, %{reason: "not_found"}}` if `{:error, _}`
  - [x] Subscribe to `"org:#{org_id}:log:#{log_id}"` via `Phoenix.PubSub.subscribe/2`
  - [x] Return `{:ok, assign(socket, log_id: log_id, organization_id: org_id)}`
- [x] Add `handle_info({:report_ready, payload}, socket)` — push `"report_ready"` to client
- [x] Add `handle_info({:pipeline_update, payload}, socket)` — push `"pipeline_update"` to client
- [x] Add `handle_info({:pipeline_failed, payload}, socket)` — push `"pipeline_failed"` to client

## 3. Register LogChannel in UserSocket

File: `lib/sitevoice_web/channels/user_socket.ex`

- [x] Add `channel "log:*", SitevoiceWeb.LogChannel` below the existing `recording:*` entry

## 4. Create BroadcastPipelineStep

File: `lib/sitevoice/reporting/steps/broadcast_pipeline_step.ex`

- [x] Define `Sitevoice.Steps.BroadcastPipelineStep` with `use Reactor.Step`
- [x] Implement `run(%{step: step_name, log_id: log_id, organization_id: org_id}, _, _)`:
  - [x] Publish `{:pipeline_update, %{step: step_name, status: :complete}}` to `"org:#{org_id}:log:#{log_id}"`
  - [x] Return `{:ok, :sent}`
- [x] Implement `compensate/4` returning `:ok`

## 5. Wire BroadcastPipelineStep into Reactor

File: `lib/sitevoice/reporting/reactors/process_recording.ex`

- [x] Add `step :broadcast_transcribed, Sitevoice.Steps.BroadcastPipelineStep` after `:save_transcript`:
  - [x] `argument :step, value("transcribed")`
  - [x] `argument :log_id, input(:log_id)`
  - [x] `argument :organization_id, input(:organization_id)`
  - [x] `wait_for :save_transcript`
- [x] Add `step :broadcast_structured, Sitevoice.Steps.BroadcastPipelineStep` after `:save_structure`:
  - [x] `argument :step, value("structured")`
  - [x] `argument :log_id, input(:log_id)`
  - [x] `argument :organization_id, input(:organization_id)`
  - [x] `wait_for :save_structure`
- [x] Add `step :broadcast_pdf_generated, Sitevoice.Steps.BroadcastPipelineStep` after `:generate_pdf`:
  - [x] `argument :step, value("pdf_generated")`
  - [x] `argument :log_id, input(:log_id)`
  - [x] `argument :organization_id, input(:organization_id)`
  - [x] `wait_for :generate_pdf`
- [x] Verify `:notify` step (BroadcastReady) still runs last and its `wait_for` / argument dependencies are intact

## 6. Write RecordingChannel Tests

File: `test/sitevoice_web/channels/recording_channel_test.exs`

- [x] Tag `@moduletag slice: :realtime`
- [x] Use `use SitevoiceWeb.ChannelCase`
- [x] Setup: create org + user, build a valid JWT socket, create a DailyLog record
- [x] Test `join/3` succeeds for the log's foreman — `assert {:ok, _, _socket} = subscribe_and_join(...)`
- [x] Test `join/3` fails for a different user — `assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(...)`
- [x] Test `handle_in("recording_complete", ...)` — assert `"processing_started"` is pushed back and an Oban job is enqueued
- [x] Test `handle_info({:report_ready, ...}, socket)` — simulate PubSub message, assert `assert_push "report_ready", _`
- [x] Test `handle_info({:pipeline_update, ...}, socket)` — simulate, assert `assert_push "pipeline_update", _`
- [x] Test `handle_info({:pipeline_failed, ...}, socket)` — simulate, assert `assert_push "pipeline_failed", _`

## 7. Write LogChannel Tests

File: `test/sitevoice_web/channels/log_channel_test.exs`

- [x] Tag `@moduletag slice: :realtime`
- [x] Use `use SitevoiceWeb.ChannelCase`
- [x] Setup: create org + user (PM role), create a DailyLog
- [x] Test `join/3` succeeds — `assert {:ok, _, _socket} = subscribe_and_join(...)`
- [x] Test `join/3` fails for non-existent log_id — `assert {:error, %{reason: "not_found"}} = subscribe_and_join(...)`
- [x] Test `handle_info({:report_ready, ...})` — assert `assert_push "report_ready", _`
- [x] Test `handle_info({:pipeline_update, ...})` — assert `assert_push "pipeline_update", _`
- [x] Test `handle_info({:pipeline_failed, ...})` — assert `assert_push "pipeline_failed", _`

## 8. Write BroadcastPipelineStep Tests

File: `test/sitevoice/reporting/steps/broadcast_pipeline_step_test.exs`

- [x] Tag `@moduletag slice: :realtime`
- [x] Test `run/3` publishes on the correct org-namespaced topic
- [x] Subscribe to the topic before calling `run/3`, then assert `assert_receive {:pipeline_update, _}`
- [x] Test returns `{:ok, :sent}`
- [x] Test `compensate/4` returns `:ok`

## 9. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:realtime` — all tests pass
- [x] `mix test` — no regressions in slices 00–05
