# Slice 06 — Real-time Channels

**Goal:** Complete the Phoenix Channel layer so foremen and PMs receive live pipeline progress
events pushed from the server. `RecordingChannel` is promoted from scaffold to fully working.
`LogChannel` is created for the PM dashboard. The Reactor emits a `pipeline_update` broadcast
after each major pipeline step.

## Acceptance Criteria

- [ ] `SitevoiceWeb.RecordingChannel.join/3` calls `Ash.Query.set_tenant(org_id)` before any Ash call,
      subscribes to `"org:#{org_id}:log:#{log_id}"` via `Phoenix.PubSub.subscribe/2`, and returns
      `{:ok, socket}` for authorized users or `{:error, %{reason: "unauthorized"}}` otherwise
- [ ] `SitevoiceWeb.RecordingChannel.handle_in("recording_complete", ...)` re-applies tenant, enqueues
      `AudioProcessor`, and pushes `"processing_started"` — behaviour unchanged from scaffold
- [ ] `SitevoiceWeb.RecordingChannel.handle_info/2` handles `{:report_ready, payload}`,
      `{:pipeline_update, payload}`, and `{:pipeline_failed, payload}` — each forwards the event to
      the connected client via `push/3` with matching event name string
- [ ] `SitevoiceWeb.LogChannel` exists with `join("log:" <> log_id, ...)`, sets tenant, verifies the
      log belongs to the user's org, subscribes to `"org:#{org_id}:log:#{log_id}"`, and forwards the
      same three PubSub messages to connected clients via `handle_info/2`
- [ ] `SitevoiceWeb.UserSocket` registers `channel "log:*", SitevoiceWeb.LogChannel`
- [ ] `Sitevoice.Steps.BroadcastPipelineStep` exists, matches `%{step:, log_id:, organization_id:}`,
      broadcasts `{:pipeline_update, %{step: step_name, status: :complete}}` on the org-namespaced
      topic, and returns `{:ok, :sent}`
- [ ] `Sitevoice.Reporting.Reactors.ProcessRecording` includes `BroadcastPipelineStep` calls with
      the label `"transcribed"` after `:save_transcript`, `"structured"` after `:save_structure`,
      and `"pdf_generated"` after `:generate_pdf`; each broadcast step has `wait_for` the preceding
      data step
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:realtime` — all tests pass
- [ ] `mix test` — no regressions in slices 00–05

## What This Slice Does NOT Include

- Email delivery of the PDF to PMs (Slice 07)
- Push notification (APNs/FCM) on report ready (Slice 07)
- Procore integration dispatch (Slice 08)
- React Native Channel client (Slice 09)
- LiveView PM dashboard UI (post-MVP)

## Key Behaviours

### PubSub Subscription Pattern

Both channels subscribe to the same org-namespaced topic on join:

```elixir
topic = "org:#{org_id}:log:#{log_id}"
Phoenix.PubSub.subscribe(Sitevoice.PubSub, topic)
```

Messages published anywhere in the system (Reactor steps, workers) on this topic arrive as
`handle_info/2` callbacks. The channel then relays them to the connected WebSocket client with
matching event name strings:

| PubSub message                | Client event        |
| ----------------------------- | ------------------- |
| `{:report_ready, payload}`    | `"report_ready"`    |
| `{:pipeline_update, payload}` | `"pipeline_update"` |
| `{:pipeline_failed, payload}` | `"pipeline_failed"` |

### BroadcastPipelineStep in the Reactor

The step is reusable — the reactor inserts it multiple times with different `:step` string labels:

```elixir
step :broadcast_transcribed, Sitevoice.Steps.BroadcastPipelineStep do
  argument :step,            value("transcribed")
  argument :log_id,          input(:log_id)
  argument :organization_id, input(:organization_id)
  wait_for :save_transcript
end
```

### Tenant Rules for Channels

- `join/3` — call `Ash.Query.set_tenant(org_id)` before any Ash operation; store `organization_id` in socket assigns
- `handle_in/3` — re-call `Ash.Query.set_tenant(socket.assigns.organization_id)` at the top of every clause
- `handle_info/2` — no Ash calls, so no tenant needed; just forward the message

### Authorization in LogChannel

PM role check: fetch the `DailyLog` using `tenant: org_id, authorize?: false`, confirm it exists
(the multitenancy filter ensures it belongs to the org). Any authenticated user in the org can
subscribe — role-level restriction is a post-MVP concern. Reject join if the log is not found.
