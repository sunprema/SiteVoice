# Slice 03 — Recording

**Goal:** `DailyLog` and `Photo` resources (tenanted), the `:submit_recording` action that uploads
audio metadata and enqueues the Oban `AudioProcessor` worker, the `SiteVoice.Storage` module for
org-prefixed Tigris key management, and a scaffold `RecordingChannel` that sets tenant on join.

## Acceptance Criteria

- [ ] `SiteVoice.Reporting` domain module exists and lists both resources
- [ ] `SiteVoice.Reporting.DailyLog` is tenanted — has `multitenancy` block, `organization_id`
      attribute, all attributes from the domain model (`date`, `status`, `audio_key`,
      `audio_duration`, `transcript`, `accuracy_score`, `labor`, `progress`, `equipment`,
      `materials`, `delays`, `safety`, `pdf_key`, `weather`, `submitted_at`)
- [ ] `DailyLog` identity `:unique_log_per_day` on `[:organization_id, :date, :foreman_id, :project_id]`
- [ ] `DailyLog` `:submit_recording` sets `organization_id` from actor, `foreman_id` from actor, `status: :pending`
- [ ] `DailyLog` `:submit_recording` enqueues `AudioProcessor` via `EnqueueProcessing` change after commit
- [ ] `DailyLog` state machine actions are defined: `:apply_transcript`, `:apply_structure`,
      `:approve_and_submit`, `:mark_failed`, `:edit_draft`, `:destroy`
- [ ] `DailyLog` read actions: `:read` (primary, loads `:pdf_url` and `:photos`),
      `:list_for_project`, `:list_for_date_range`
- [ ] `DailyLog` calculations: `pdf_url`, `audio_url`, `is_late`
- [ ] `DailyLog` all Ash Policies match the policy matrix (submit_recording, apply_transcript,
      apply_structure, edit_draft, approve_and_submit, read, destroy, mark_failed)
- [ ] `SiteVoice.Reporting.Photo` is tenanted — has `multitenancy` block, `organization_id`,
      `storage_key`, `caption`, `category`, `taken_at`
- [ ] `Photo` `:upload` sets `organization_id` from actor; `:apply_caption` allows nil actor (Reactor)
- [ ] `Photo` calculations: `url` (presigned Tigris URL)
- [ ] `Photo` policies match policy matrix
- [ ] `Reporting.Changes.EnqueueProcessing` uses `after_action` to insert `AudioProcessor` job
      with `%{log_id: ..., organization_id: ...}` after successful DailyLog create
- [ ] `Reporting.Changes.DispatchIntegrations` is defined (may be a stub returning `{:ok, log}` for now)
- [ ] `Reporting.Calculations.PdfUrl` returns presigned URL from Tigris for `pdf_key` (nil if no key)
- [ ] `Reporting.Calculations.AudioUrl` returns presigned URL from Tigris for `audio_key`
- [ ] `Reporting.Calculations.IsLate` returns `true` if `submitted_at` is after 6 PM on `date`
- [ ] `Reporting.Calculations.PhotoUrl` returns presigned URL for photo `storage_key`
- [ ] `SiteVoice.Workers.AudioProcessor` uses `queue: :audio, max_attempts: 3`;

# pass tenant to every Ash call

- [ ] `SiteVoice.Storage` module has `audio_key/4`, `photo_key/4`, `pdf_key/3`,
      `store_audio/2`, `store_photo/2`, `fetch/2`, `presigned_url/3` functions
- [ ] `Organization` gains `has_many :daily_logs, SiteVoice.Reporting.DailyLog` (if not already from domain model)
- [ ] `Project` gains `has_many :daily_logs, SiteVoice.Reporting.DailyLog`
- [ ] `User` has_many `:daily_logs` relationship (already declared in domain model — verify it compiles)
- [ ] AshJsonApi routes wired for DailyLogs (`POST /daily-logs`, `GET /daily-logs/:id`,
      `PATCH /daily-logs/:id`, `DELETE /daily-logs/:id`)
- [ ] AshJsonApi routes wired for Photos (`POST /photos`, `GET /photos/:id`, `DELETE /photos/:id`)
- [ ] `SiteVoice.Reporting` added to `ash_domains` in config and to `AshJsonApiRouter` domains list
- [ ] `RecordingChannel` scaffold exists at `lib/sitevoice_web/channels/recording_channel.ex`:
  - `join("recording:" <> log_id)` sets tenant, checks ownership, assigns `organization_id` and `log_id`
  - `handle_in("recording_complete")` re-sets tenant, inserts AudioProcessor job, pushes `"processing_started"`
- [ ] `UserSocket` exists and authenticates JWT, sets `current_user` on socket assigns
- [ ] `Projects.Calculations.ReportCount` now returns real count of submitted DailyLogs (not stub 0)
- [ ] `Projects.Calculations.LastReportDate` now returns real date (not stub nil)
- [ ] `mix ash.codegen recording_resources` generates migration with `daily_logs` and `photos` tables
- [ ] `mix ash.setup` runs clean after migration
- [ ] All recording tests pass (`mix test --only slice:recording`)
- [ ] `mix test` — no regressions in other tests

## What This Slice Does NOT Include

- No Whisper transcription or Claude API calls (Slice 04)
- No PDF generation (Slice 05)
- No full Phoenix Channel pipeline broadcasts (Slice 06)
- No Procore/integration dispatch implementation (Slice 08)
- No mobile client (Slice 09)
- `AudioProcessor.perform/1` delegates to ProcessRecording Reactor which does NOT exist yet —
  the worker should call the Reactor stub (or log a placeholder) without crashing

## Key Behaviors

### EnqueueProcessing Change

Fires inside `Ash.Changeset.after_action/2` so the Oban job is only inserted after the
DailyLog row is committed. Job args must include `organization_id` explicitly:

```elixir
%{log_id: log.id, organization_id: log.organization_id}
|> SiteVoice.Workers.AudioProcessor.new()
|> Oban.insert!()
```

### AudioProcessor Worker

`perform/1` must set tenant before any Ash calls. In this slice, the Reactor does not exist yet —
the worker should attempt to call `SiteVoice.Reporting.Reactors.ProcessRecording.run/1` but that
module will be created in Slice 04. For now, define the worker so it compiles and the perform/1
function logs the intent and returns `:ok` without crashing.

### RecordingChannel Authorization

On `join`, after setting tenant, verify the current user owns the log being joined:

```elixir
if authorized?(socket, log_id) do
  {:ok, assign(socket, log_id: log_id, organization_id: org_id)}
else
  {:error, %{reason: "unauthorized"}}
end
```

`authorized?/2` checks that a DailyLog with the given `log_id` exists and its `foreman_id`
matches `socket.assigns.current_user.id`.

### Presigned URL Calculations

`PdfUrl`, `AudioUrl`, and `PhotoUrl` all return `nil` when the key is `nil`. When the key exists,
they call `SiteVoice.Storage.presigned_url/3`. The 1-hour expiry is the default.

### IsLate Calculation

Returns `true` when `submitted_at` is not nil and the time-of-day component of `submitted_at`
is after 18:00 in the project's timezone (or UTC if no timezone). Returns `false` otherwise.
For MVP, comparing against UTC 18:00 is acceptable.

### ReportCount and LastReportDate (now real implementations)

These were stubbed in Slice 02. Now that DailyLog exists, implement them:

- `ReportCount`: count DailyLogs where `project_id == record.id and status == :submitted`
- `LastReportDate`: return max `date` from DailyLogs where `project_id == record.id and status == :submitted`
