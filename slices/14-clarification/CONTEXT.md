# Context — Slice 14: Conversational Clarification + Per-Project Daily Log Brief

## Dependency

Slices 02 (Projects), 03 (Recording), 04 (AI Pipeline), 05 (PDF Generation), 06 (Real-time),
and 08 (LiveView) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `lib/sitevoice/projects/project.ex` — `Project` resource; baseline for the new daily-log brief
   attributes and the `:update_daily_log_brief` action
2. `lib/sitevoice/reporting/daily_log.ex` — `DailyLog` resource; note the existing status enum
   `[:pending, :processing, :draft, :submitted, :failed]` (adding `:awaiting_clarification`),
   the `:submit_recording`, `:apply_structure`, `:apply_transcript`, `:mark_failed`,
   `:approve_and_submit`, and `:edit_draft` actions
3. `lib/sitevoice/reporting/reactors/process_recording.ex` — the existing pipeline that will
   be split into `ProcessRecording` (extraction half) + `FinalizeReport` (photos + PDF tail)
4. `lib/sitevoice/reporting/steps/structure_with_claude.ex` — Claude prompt to extend with
   project-aware context (`daily_log_context`, `required_sections`)
5. `lib/sitevoice/reporting/steps/transcribe_whisper.ex` — Whisper call to reuse for the
   clarification addendum
6. `lib/sitevoice/reporting/steps/broadcast_pipeline_step.ex` — broadcast pattern; extend with
   the new `"clarification_needed"` step name
7. `lib/sitevoice/reporting/changes/enqueue_processing.ex` — clone pattern for
   `EnqueueClarification` and `EnqueueFinalize`
8. `lib/sitevoice/workers/audio_processor.ex` — worker pattern for `ClarificationProcessor` and
   `FinalizeReportWorker`
9. `lib/sitevoice_web/channels/recording_channel.ex` — channel pattern; new `handle_in`
   callbacks and the `:clarification_needed` push
10. `lib/sitevoice_web/channels/log_channel.ex` — mirror new broadcast
11. `lib/sitevoice_web/live/logs/processing_live.ex` — LiveView that will navigate to the new
    clarification screen
12. `lib/sitevoice_web/live/logs/new_live.ex` — pattern for the addendum audio upload widget
13. `lib/sitevoice/storage.ex` — `audio_key/4` and `store_audio/2`; new key prefix is
    `{org_id}/audio/clarifications/{log_id}/...`
14. `docs/CODING_STANDARDS.md` — file layout and naming conventions
15. `CLAUDE.md` — Architecture Rules §Ash, §Multitenancy, §Reactor, §Oban

## Existing State

- `lib/sitevoice/projects/project.ex` — needs three new attributes and one new action
- `lib/sitevoice/reporting/daily_log.ex` — needs status enum extension, new clarification
  attributes, new actions
- `lib/sitevoice/reporting/reactors/process_recording.ex` — needs to be trimmed to the
  extraction half; the tail (photos → PDF → notify) moves to `FinalizeReport`
- `lib/sitevoice/reporting/steps/structure_with_claude.ex` — needs to load the project and
  inject `daily_log_context` + `required_sections` into the prompt
- `lib/sitevoice_web/channels/recording_channel.ex` — needs new `handle_in` and `handle_info`
- `lib/sitevoice_web/channels/log_channel.ex` — needs new `handle_info`
- `lib/sitevoice_web/live/logs/processing_live.ex` — needs to handle `:clarification_needed`
- `lib/sitevoice_web/router.ex` — needs new live routes
- `lib/sitevoice_web/live/projects/` — needs the brief form component wired into create + edit

## New Files To Create

### Ash Resource Steps & Reactors

- `lib/sitevoice/reporting/steps/assess_completeness.ex` — rule-based decision step that loads
  the project's `required_sections` and `daily_log_min_accuracy`, compares against the
  extracted structured fields, returns `{:ok, :complete}` or
  `{:ok, {:incomplete, missing_sections}}`
- `lib/sitevoice/reporting/steps/generate_clarifications.ex` — Claude call that takes the
  transcript, structured output, `daily_log_context`, and missing sections; returns 1–3
  `%{question: String.t(), missing_field: atom()}`. Falls back to deterministic templates on
  Claude failure
- `lib/sitevoice/reporting/steps/save_clarification_request.ex` — calls `:request_clarification`
  on the DailyLog, persisting the questions and transitioning status to `:awaiting_clarification`
- `lib/sitevoice/reporting/steps/broadcast_clarification_needed.ex` — broadcasts
  `{:clarification_needed, %{questions: [...]}}` to `"org:{org_id}:log:{log_id}"`
- `lib/sitevoice/reporting/steps/fetch_clarification_audio.ex` — fetches the addendum audio
  binary from Tigris using `clarification_audio_key`
- `lib/sitevoice/reporting/steps/transcribe_clarification.ex` — thin wrapper around Whisper
  for the addendum (or reuse `TranscribeWhisper` if its signature allows)
- `lib/sitevoice/reporting/steps/save_clarification_transcript.ex` — persists the addendum
  transcript via the new `:apply_clarification_transcript` action
- `lib/sitevoice/reporting/steps/merge_clarification.ex` — Claude call that re-structures using
  the project brief + original transcript + clarification transcript; returns updated structured
  fields
- `lib/sitevoice/reporting/reactors/process_clarification.ex` — addendum pipeline:
  `set_tenant` → `fetch_log` → `fetch_clarification_audio` → `transcribe_clarification` →
  `save_clarification_transcript` → `merge_clarification` → `save_structure` →
  `enqueue_finalize`
- `lib/sitevoice/reporting/reactors/finalize_report.ex` — tail extracted from the current
  `ProcessRecording`: `set_tenant` → `fetch_log` → `caption_photos` →
  `broadcast_structured` → `generate_pdf` → `store_pdf` → `save_pdf_key` →
  `broadcast_pdf_generated` → `notify`

### Ash Changes

- `lib/sitevoice/reporting/changes/enqueue_clarification.ex` — post-action change that enqueues
  `ClarificationProcessor` after `:submit_clarification`
- `lib/sitevoice/reporting/changes/enqueue_finalize.ex` — post-action change that enqueues
  `FinalizeReportWorker` after `assess_completeness` reports `:complete` or after
  `:skip_clarification` runs

### Oban Workers

- `lib/sitevoice/workers/clarification_processor.ex` — queue `:audio`, `max_attempts: 3`; runs
  `ProcessClarification` reactor; on failure calls `mark_failed`
- `lib/sitevoice/workers/finalize_report_worker.ex` — queue `:audio` (same as
  `AudioProcessor`), `max_attempts: 3`; runs `FinalizeReport` reactor; on failure calls
  `mark_failed` and broadcasts `:pipeline_failed`

### LiveView

- `lib/sitevoice_web/live/logs/clarification_live.ex` — `SitevoiceWeb.Logs.ClarificationLive`
  - Route: `/logs/:id/clarify`
  - Mounts with the DailyLog and its persisted `clarification_questions`
  - Renders the questions and an audio upload widget (mirrors `NewLive`'s upload pattern)
  - "Skip" button → calls `:skip_clarification` → navigates to `/logs/:id/processing`
  - On audio upload complete → calls `:submit_clarification` → navigates to
    `/logs/:id/processing`
- `lib/sitevoice_web/live/projects/brief_form_component.ex` — LiveComponent for the daily-log
  brief: section toggle checkboxes (`labor`, `progress`, `equipment`, `materials`, `delays`,
  `safety`, `weather`), free-text `daily_log_context` textarea (~1000 chars),
  `daily_log_min_accuracy` number input (range 0.0–1.0, step 0.05, default 0.7)

### Migrations

- `priv/repo/migrations/<ts>_add_daily_log_brief_to_projects.exs` — adds
  `required_sections` ({:array, :atom}, default `["labor", "progress", "safety"]`),
  `daily_log_context` (:string, default seed), `daily_log_min_accuracy` (:float, default 0.7)
- `priv/repo/migrations/<ts>_add_clarification_to_daily_logs.exs` — adds
  `clarification_questions` ({:array, :map}, default []),
  `clarification_audio_key` (:string),
  `clarification_audio_duration` (:integer),
  `clarification_transcript` (:string),
  `clarification_round` (:integer, default 0); extends status enum to include
  `awaiting_clarification`

### Tests

- `test/sitevoice/projects/project_brief_test.exs` — resource tests for the three new
  attributes, default seed, `:update_daily_log_brief` policy enforcement
- `test/sitevoice/reporting/daily_log_clarification_test.exs` — tests for new actions
  (`:request_clarification`, `:submit_clarification`, `:skip_clarification`,
  `:apply_clarification_transcript`) and the `:awaiting_clarification` status transition
- `test/sitevoice/reporting/steps/assess_completeness_test.exs` — rule logic against the
  project brief
- `test/sitevoice/reporting/steps/generate_clarifications_test.exs` — Claude call with
  `Req.Test` stubs + template fallback when Claude fails
- `test/sitevoice/reporting/steps/merge_clarification_test.exs` — Claude re-structure stub
- `test/sitevoice/reporting/reactors/process_clarification_test.exs` — integration test for
  the addendum pipeline
- `test/sitevoice/reporting/reactors/finalize_report_test.exs` — integration test for the
  PDF tail
- `test/sitevoice/reporting/reactors/process_recording_branching_test.exs` — covers both
  branches: complete → enqueues `FinalizeReportWorker`; incomplete → broadcasts
  `:clarification_needed`
- `test/sitevoice_web/channels/recording_channel_clarification_test.exs` — new `handle_in`
  callbacks
- `test/sitevoice_web/live/logs/clarification_live_test.exs` — skip + submit flows

## Existing Files To Modify

- `lib/sitevoice/projects/project.ex` — add three attributes, `:update_daily_log_brief` action,
  policy restricting it to PM/org_admin; extend `:create` accept list
- `lib/sitevoice/reporting/daily_log.ex` — extend status enum, add five clarification
  attributes, add four new actions, add policies for those actions
- `lib/sitevoice/reporting/reactors/process_recording.ex` — trim to the extraction half;
  after `save_structure`, run `assess_completeness`; on `:complete` enqueue
  `FinalizeReportWorker`; on `:incomplete` run `generate_clarifications` →
  `save_clarification_request` → `broadcast_clarification_needed` and stop
- `lib/sitevoice/reporting/steps/structure_with_claude.ex` — load the project (already
  reachable via `log.project_id`); inject `daily_log_context` and `required_sections` into the
  system prompt; instruct Claude to lower `accuracy_score` when required sections lack
  coverage
- `lib/sitevoice_web/channels/recording_channel.ex`
  - new `handle_in("clarification_complete", %{"audio_key" => ..., "audio_duration" => ...})`
    → calls `:submit_clarification` → enqueues `ClarificationProcessor`
  - new `handle_in("skip_clarification", _)` → calls `:skip_clarification` → enqueues
    `FinalizeReportWorker`
  - new `handle_info({:clarification_needed, payload})` → `push(socket, "clarification_needed",
    payload)`
- `lib/sitevoice_web/channels/log_channel.ex` — mirror the new `handle_info`
- `lib/sitevoice_web/live/logs/processing_live.ex` — subscribe to `:clarification_needed`;
  on receipt, `push_navigate` to `/logs/:id/clarify`
- `lib/sitevoice_web/router.ex` — `live "/logs/:id/clarify", Logs.ClarificationLive`; add
  project brief edit route inside the authenticated scope
- `lib/sitevoice_web/live/projects/new_live.ex` (and equivalent edit/settings LiveView) —
  embed `BriefFormComponent`
- `CLAUDE.md` — mark Slice 14 in the slice status table

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- `require Ash.Query` wherever `Ash.Query` macros are used
- `organization_id` is never accepted from API request bodies — internal only
- `clarification_round` is server-managed — never accepted from the client
- The clarification cap is enforced in both `assess_completeness` (won't trigger when
  `round >= 1`) **and** in `:submit_clarification` (refuses when `round >= 1`)
- All new Oban job args include `organization_id`; `set_tenant` is the first step of every
  new reactor
- All PubSub broadcasts use the existing `"org:{org_id}:log:{log_id}"` topic — never bare
- Clarification audio storage key: `{organization_id}/audio/clarifications/{log_id}/{uuid}.m4a`
- Use `Req.Test` stubs for Claude and Whisper in tests — never hit real endpoints
- All tests tagged `@moduletag slice: :clarification`
- Claude model: `claude-sonnet-4-20250514` (matches the rest of the project)
- `mix compile --warnings-as-errors` — zero warnings
