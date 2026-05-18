# Tasks — Slice 14: Conversational Clarification + Per-Project Daily Log Brief

Work through in order. Check off each task as it is completed.

---

## 1. Extend `Project` Resource With Brief Attributes

File: `lib/sitevoice/projects/project.ex`

- [ ] Add attribute `required_sections` of type `{:array, :atom}` with
      `constraints: [items: [one_of: [:labor, :progress, :equipment, :materials, :delays, :safety, :weather]]]`,
      `default: [:labor, :progress, :safety]`, `public?: true`
- [ ] Add attribute `daily_log_context` of type `:string` with the default seed text from
      SLICE.md, `public?: true`
- [ ] Add attribute `daily_log_min_accuracy` of type `:float` with
      `constraints: [min: 0.0, max: 1.0]`, `default: 0.7`, `public?: true`
- [ ] Extend `:create` action's `accept` list to include the three new attributes
- [ ] Add new action `:update_daily_log_brief` (update; accept the three new attributes)
- [ ] Add policy block for `:update_daily_log_brief` authorizing `:pm` and `:org_admin`

## 2. Migration For Project Brief

- [ ] Run `mix ash.codegen add_daily_log_brief_to_projects`
- [ ] Review generated migration; confirm column types, defaults, and that existing rows
      backfill correctly
- [ ] Run `mix ash.migrate`

## 3. Extend `DailyLog` Resource With Clarification Attributes

File: `lib/sitevoice/reporting/daily_log.ex`

- [ ] Extend `status` constraints `one_of` list to
      `[:pending, :processing, :awaiting_clarification, :draft, :submitted, :failed]`
- [ ] Add attribute `clarification_questions` ({:array, :map}, default `[]`)
- [ ] Add attribute `clarification_audio_key` (:string)
- [ ] Add attribute `clarification_audio_duration` (:integer)
- [ ] Add attribute `clarification_transcript` (:string)
- [ ] Add attribute `clarification_round` (:integer, default `0`)

## 4. New `DailyLog` Actions

File: `lib/sitevoice/reporting/daily_log.ex`

- [ ] `:request_clarification` — update; `accept [:clarification_questions]`;
      `change set_attribute(:status, :awaiting_clarification)`
- [ ] `:submit_clarification` — update; `accept [:clarification_audio_key, :clarification_audio_duration]`;
      `require_atomic? false`;
      use a `before_action` to error when `data.clarification_round >= 1`;
      `change set_attribute(:status, :processing)`;
      `change Sitevoice.Reporting.Changes.EnqueueClarification`
- [ ] `:apply_clarification_transcript` — update; `accept [:clarification_transcript]`
- [ ] `:skip_clarification` — update; `require_atomic? false`;
      `change set_attribute(:status, :processing)`;
      `change Sitevoice.Reporting.Changes.EnqueueFinalize`

## 5. Update Policies On `DailyLog`

File: `lib/sitevoice/reporting/daily_log.ex`

- [ ] Policy for `:request_clarification` and `:apply_clarification_transcript`:
      `authorize_if actor_absent()` and `authorize_if actor_attribute_equals(:role, :org_admin)`
- [ ] Policy for `:submit_clarification` and `:skip_clarification`:
      `authorize_if relates_to_actor_via(:foreman)` and
      `authorize_if actor_attribute_equals(:role, :org_admin)`

## 6. Migration For DailyLog Clarification

- [ ] Run `mix ash.codegen add_clarification_to_daily_logs`
- [ ] Review generated migration; confirm enum extension, column types, and defaults
- [ ] Run `mix ash.migrate`

## 7. New Change Modules

File: `lib/sitevoice/reporting/changes/enqueue_clarification.ex`

- [ ] Define `Sitevoice.Reporting.Changes.EnqueueClarification` with `use Ash.Resource.Change`
- [ ] Implement `change/2` that registers an `after_action` hook
- [ ] In the hook: build job args `%{log_id: log.id, organization_id: log.organization_id}`
      and call `Sitevoice.Workers.ClarificationProcessor.new(args) |> Oban.insert!()`

File: `lib/sitevoice/reporting/changes/enqueue_finalize.ex`

- [ ] Define `Sitevoice.Reporting.Changes.EnqueueFinalize` with `use Ash.Resource.Change`
- [ ] Same shape as above but enqueues `Sitevoice.Workers.FinalizeReportWorker`

## 8. `AssessCompleteness` Step

File: `lib/sitevoice/reporting/steps/assess_completeness.ex`

- [ ] Define `Sitevoice.Reporting.Steps.AssessCompleteness` with `use Reactor.Step`
- [ ] `run/3` arguments: `log` (with project_id), `organization_id`
- [ ] Load `Sitevoice.Projects.Project` by `log.project_id` with
      `tenant: organization_id, authorize?: false`
- [ ] If `log.clarification_round >= 1`, return `{:ok, :complete}` (cap enforced)
- [ ] If `log.accuracy_score < project.daily_log_min_accuracy`, return
      `{:ok, {:incomplete, [:accuracy]}}`
- [ ] For each section in `project.required_sections`, check if the corresponding DailyLog
      field is empty/blank; collect missing sections
- [ ] If any missing, return `{:ok, {:incomplete, missing_sections}}`
- [ ] Otherwise return `{:ok, :complete}`
- [ ] `compensate/4` — return `:ok`

## 9. `GenerateClarifications` Step

File: `lib/sitevoice/reporting/steps/generate_clarifications.ex`

- [ ] Define `Sitevoice.Reporting.Steps.GenerateClarifications` with `use Reactor.Step`
- [ ] `run/3` arguments: `log`, `project`, `missing_sections`
- [ ] Build a prompt as described in SLICE.md (includes brief + transcript + extracted JSON +
      missing sections)
- [ ] Call Claude (`claude-sonnet-4-20250514`, `max_tokens: 600`, `timeout: 15_000`) via
      `Req.post!/2`
- [ ] Parse JSON; coerce `missing_field` to atom; cap result at 3 questions
- [ ] On any Claude failure or parse error, build deterministic templates from
      `missing_sections` (see SLICE.md fallback list)
- [ ] Return `{:ok, [%{question: String.t(), missing_field: atom()}, ...]}`
- [ ] `compensate/4` — return `:ok`

## 10. `SaveClarificationRequest` Step

File: `lib/sitevoice/reporting/steps/save_clarification_request.ex`

- [ ] Define `Sitevoice.Reporting.Steps.SaveClarificationRequest` with `use Reactor.Step`
- [ ] `run/3`: call `DailyLog :request_clarification` with `clarification_questions: questions`,
      `tenant: org_id, authorize?: false`
- [ ] Return `{:ok, updated_log}`
- [ ] `compensate/4` — return `:ok`

## 11. `BroadcastClarificationNeeded` Step

File: `lib/sitevoice/reporting/steps/broadcast_clarification_needed.ex`

- [ ] Define `Sitevoice.Reporting.Steps.BroadcastClarificationNeeded` with `use Reactor.Step`
- [ ] `run/3`: `Phoenix.PubSub.broadcast(Sitevoice.PubSub, "org:#{org_id}:log:#{log_id}",
      {:clarification_needed, %{log_id: log_id, questions: questions}})`
- [ ] Return `{:ok, :broadcasted}`
- [ ] `compensate/4` — return `:ok`

## 12. Refactor `ProcessRecording` Reactor

File: `lib/sitevoice/reporting/reactors/process_recording.ex`

- [ ] Keep steps up to and including `save_structure`
- [ ] Add `assess_completeness` step after `save_structure`, wait_for `save_structure`
- [ ] Add a `switch` step (or use Reactor's branching) on the result:
  - [ ] `:complete` branch → run a small step that enqueues
        `Sitevoice.Workers.FinalizeReportWorker` and returns
  - [ ] `{:incomplete, missing}` branch → fetch the project (or pass it through) →
        `generate_clarifications` → `save_clarification_request` →
        `broadcast_clarification_needed` and return
- [ ] Remove `caption_photos`, `broadcast_structured`, `generate_pdf`, `store_pdf`,
      `save_pdf_key`, `broadcast_pdf_generated`, `notify` from this reactor (they move to
      `FinalizeReport`)

## 13. `FinalizeReport` Reactor

File: `lib/sitevoice/reporting/reactors/finalize_report.ex`

- [ ] Define `Sitevoice.Reporting.Reactors.FinalizeReport` with `use Reactor`
- [ ] Inputs: `log_id`, `organization_id`
- [ ] Steps: `set_tenant` → `fetch_log` (with photos preload) → `caption_photos` →
      `broadcast_structured` → `generate_pdf` → `store_pdf` → `save_pdf_key` →
      `broadcast_pdf_generated` → `notify`
- [ ] Reuse existing step modules — do not duplicate

## 14. `FinalizeReportWorker`

File: `lib/sitevoice/workers/finalize_report_worker.ex`

- [ ] Define `Sitevoice.Workers.FinalizeReportWorker` with
      `use Oban.Worker, queue: :audio, max_attempts: 3`
- [ ] `perform/1`: extract `log_id`, `organization_id`; `Ash.set_tenant(org_id)`;
      run `Sitevoice.Reporting.Reactors.FinalizeReport`
- [ ] On error: call `DailyLog :mark_failed` and broadcast `{:pipeline_failed, payload}`

## 15. `FetchClarificationAudio` Step

File: `lib/sitevoice/reporting/steps/fetch_clarification_audio.ex`

- [ ] Define `Sitevoice.Reporting.Steps.FetchClarificationAudio` with `use Reactor.Step`
- [ ] `run/3`: use `Sitevoice.Storage` to download `log.clarification_audio_key`
- [ ] Return `{:ok, binary}`
- [ ] `compensate/4` — return `:ok`

## 16. `TranscribeClarification` Step

File: `lib/sitevoice/reporting/steps/transcribe_clarification.ex`

- [ ] Thin wrapper around `TranscribeWhisper` (or extend the existing module to accept an
      input-key argument and reuse) — preference is reuse via argument
- [ ] Returns `{:ok, transcript_string}`

## 17. `SaveClarificationTranscript` Step

File: `lib/sitevoice/reporting/steps/save_clarification_transcript.ex`

- [ ] Define `Sitevoice.Reporting.Steps.SaveClarificationTranscript` with `use Reactor.Step`
- [ ] `run/3`: call `DailyLog :apply_clarification_transcript` with the new transcript
- [ ] Return `{:ok, updated_log}`

## 18. `MergeClarification` Step

File: `lib/sitevoice/reporting/steps/merge_clarification.ex`

- [ ] Define `Sitevoice.Reporting.Steps.MergeClarification` with `use Reactor.Step`
- [ ] `run/3`: build Claude prompt with project brief + original transcript + extracted
      structured fields + clarification transcript
- [ ] Call Claude (`claude-sonnet-4-20250514`, `max_tokens: 2000`, `timeout: 30_000`)
- [ ] Parse JSON; return `{:ok, %{labor:, progress:, equipment:, materials:, delays:, safety:,
      accuracy_score:}}`
- [ ] On Claude failure, return `{:error, reason}` (Oban will retry)
- [ ] `compensate/4` — return `:ok`

## 19. `ProcessClarification` Reactor

File: `lib/sitevoice/reporting/reactors/process_clarification.ex`

- [ ] Define `Sitevoice.Reporting.Reactors.ProcessClarification` with `use Reactor`
- [ ] Inputs: `log_id`, `organization_id`
- [ ] Step order: `set_tenant` → `fetch_log` → `fetch_clarification_audio` →
      `transcribe_clarification` → `save_clarification_transcript` → `merge_clarification` →
      `save_structure` (calls `:apply_structure` with merged fields and increments
      `clarification_round`) → `enqueue_finalize` (a tiny step that enqueues
      `FinalizeReportWorker`)
- [ ] `compensate/4` on terminal step: call `:mark_failed` + broadcast `:pipeline_failed`

## 20. `ClarificationProcessor` Worker

File: `lib/sitevoice/workers/clarification_processor.ex`

- [ ] Define `Sitevoice.Workers.ClarificationProcessor` with
      `use Oban.Worker, queue: :audio, max_attempts: 3`
- [ ] `perform/1`: extract args; `Ash.set_tenant(org_id)`; run `ProcessClarification` reactor
- [ ] On error: call `DailyLog :mark_failed` and broadcast `{:pipeline_failed, payload}`

## 21. Project-Aware `StructureWithClaude`

File: `lib/sitevoice/reporting/steps/structure_with_claude.ex`

- [ ] Load `Project` by `log.project_id` (tenant: org_id, authorize?: false)
- [ ] Inject `project.daily_log_context` and `Enum.join(project.required_sections, ", ")`
      into the system prompt
- [ ] Add an instruction to lower `accuracy_score` when required sections lack coverage
- [ ] Keep the existing JSON schema unchanged for backward compatibility with the rest of the
      pipeline

## 22. Channel Updates

File: `lib/sitevoice_web/channels/recording_channel.ex`

- [ ] Add `handle_info({:clarification_needed, payload}, socket)` that pushes
      `"clarification_needed"` to the client
- [ ] Add `handle_in("clarification_complete", %{"audio_key" => ak, "audio_duration" => d}, socket)`:
  - [ ] Verify socket's user is the log's foreman
  - [ ] Re-apply tenant
  - [ ] Call `DailyLog :submit_clarification` with the two attributes
  - [ ] Push `"clarification_processing"` to client; reply `{:reply, :ok, socket}`
- [ ] Add `handle_in("skip_clarification", _, socket)`:
  - [ ] Verify foreman; re-apply tenant; call `DailyLog :skip_clarification`
  - [ ] Reply `{:reply, :ok, socket}`

File: `lib/sitevoice_web/channels/log_channel.ex`

- [ ] Mirror `handle_info({:clarification_needed, payload}, socket)`

## 23. LiveView — Processing Page Navigation

File: `lib/sitevoice_web/live/logs/processing_live.ex`

- [ ] Subscribe to the same PubSub topic the channel uses; on
      `{:clarification_needed, payload}`, `push_navigate(socket, to: ~p"/logs/#{log.id}/clarify")`

## 24. LiveView — `ClarificationLive`

File: `lib/sitevoice_web/live/logs/clarification_live.ex`

- [ ] Define `SitevoiceWeb.Logs.ClarificationLive` with `use SitevoiceWeb, :live_view`
- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: load the log (must be foreman or admin); assign `:log`, `:questions`,
      `:upload_config`
- [ ] Render a list of questions
- [ ] Render an audio upload widget (mirror `NewLive`'s upload logic; `.m4a/.mp3/.wav/.ogg`,
      50MB max)
- [ ] `handle_event("skip", _, socket)` — calls `:skip_clarification`; `push_navigate` to
      `/logs/:id/processing`
- [ ] On upload completion:
  - [ ] Compute key `{org_id}/audio/clarifications/{log_id}/{uuid}.m4a`
  - [ ] Call `Sitevoice.Storage.store_audio/2`
  - [ ] Call `:submit_clarification` with the new key + duration
  - [ ] `push_navigate` to `/logs/:id/processing`

## 25. Brief Form Component

File: `lib/sitevoice_web/live/projects/brief_form_component.ex`

- [ ] Define `SitevoiceWeb.Projects.BriefFormComponent` with `use SitevoiceWeb, :live_component`
- [ ] Render section toggle checkboxes for each of `[:labor, :progress, :equipment, :materials,
      :delays, :safety, :weather]`
- [ ] Render `daily_log_context` textarea with a `maxlength` of 1000 and a small character counter
- [ ] Render `daily_log_min_accuracy` number input (step 0.05, min 0.0, max 1.0)
- [ ] Emit form events the parent LiveView can subscribe to

## 26. Wire `BriefFormComponent` Into Project Create and Edit

Files: `lib/sitevoice_web/live/projects/new_live.ex`, project settings/edit LiveView

- [ ] Embed `BriefFormComponent` in the project creation form; submit form passes all four
      blocks to `:create` action
- [ ] Embed `BriefFormComponent` in a new project settings/edit LiveView (route inside
      authenticated scope, e.g. `/projects/:id/settings`)
- [ ] Page denies non-PM/admin users via Ash policy on `:update_daily_log_brief`

## 27. Router Updates

File: `lib/sitevoice_web/router.ex`

- [ ] Add `live "/logs/:id/clarify", Logs.ClarificationLive` inside the authenticated scope
- [ ] Add `live "/projects/:id/settings", Projects.SettingsLive` (or equivalent) for editing
      the brief

## 28. CLAUDE.md Status Table

File: `CLAUDE.md`

- [ ] Update the Slice Status table: change Slice 14 row to status `🔨 In progress` when work
      starts; flip to `✅ Complete` once all verification passes

## 29. Tests

All tagged `@moduletag slice: :clarification`. Use `Req.Test` stubs for Claude and Whisper.

File: `test/sitevoice/projects/project_brief_test.exs`

- [ ] `:create` accepts the new fields and applies defaults when omitted
- [ ] `:update_daily_log_brief` rejects non-PM/admin actors
- [ ] PM can update; values round-trip

File: `test/sitevoice/reporting/daily_log_clarification_test.exs`

- [ ] `:request_clarification` transitions to `:awaiting_clarification`, persists questions
- [ ] `:submit_clarification` rejects when `clarification_round >= 1`
- [ ] `:skip_clarification` transitions to `:processing` and enqueues `FinalizeReportWorker`
- [ ] `:apply_clarification_transcript` persists transcript

File: `test/sitevoice/reporting/steps/assess_completeness_test.exs`

- [ ] Complete case (all required sections populated, accuracy ≥ threshold)
- [ ] Empty required section → `{:incomplete, [section]}`
- [ ] `accuracy_score < threshold` → `{:incomplete, [:accuracy]}`
- [ ] `clarification_round == 1` → always returns `:complete`

File: `test/sitevoice/reporting/steps/generate_clarifications_test.exs`

- [ ] Claude returns valid JSON → questions parsed
- [ ] Claude returns malformed body → falls back to deterministic templates per missing section
- [ ] Claude timeout → falls back to templates

File: `test/sitevoice/reporting/steps/merge_clarification_test.exs`

- [ ] Stub Claude with merged JSON; verify returned structure

File: `test/sitevoice/reporting/reactors/process_clarification_test.exs`

- [ ] Full integration with Whisper + Claude stubs; ends with status `:processing` and
      `FinalizeReportWorker` enqueued

File: `test/sitevoice/reporting/reactors/finalize_report_test.exs`

- [ ] Full integration; ends with status `:draft`, pdf_key set, `:report_ready` broadcast

File: `test/sitevoice/reporting/reactors/process_recording_branching_test.exs`

- [ ] Complete extraction → `FinalizeReportWorker` enqueued (no clarification broadcast)
- [ ] Incomplete extraction → `:clarification_needed` broadcast, status
      `:awaiting_clarification`, questions persisted, no `FinalizeReportWorker` enqueued

File: `test/sitevoice_web/channels/recording_channel_clarification_test.exs`

- [ ] Foreman can send `clarification_complete`; non-foreman is rejected
- [ ] Skip path enqueues `FinalizeReportWorker`

File: `test/sitevoice_web/live/logs/clarification_live_test.exs`

- [ ] Skip flow ends on `/logs/:id/processing`
- [ ] Submit flow stores audio + calls `:submit_clarification`

## 30. Verify

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:clarification` — all tests pass
- [ ] `mix test` — no regressions in slices 00–13
- [ ] Manual dev smoke test: hospital project with custom `daily_log_context` produces
      hospital-flavored questions when given a labor-less recording; Skip path produces an
      empty-labor draft; happy path produces a draft with merged labor entries
