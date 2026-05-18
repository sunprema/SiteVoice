# Slice 14 — Conversational Clarification + Per-Project Daily Log Brief

**Goal:** When a foreman uploads a voice memo and the AI pipeline can't extract the project's
required information, pause the pipeline, present 1–3 targeted voice questions, accept a short
addendum recording, merge the new info, then finalize the PDF. The foreman can always Skip and
go straight to draft review. Trigger logic is driven by a per-project "daily log brief" the PM
sets up at project creation — a list of required sections plus free-text project context — so
both extraction and clarification questions are project-aware.

## Acceptance Criteria

### Project Brief

- [ ] `Sitevoice.Projects.Project` gains three attributes:
  - [ ] `required_sections` ({:array, :atom}, constraints
        `[items: [one_of: [:labor, :progress, :equipment, :materials, :delays, :safety, :weather]]]`,
        default `[:labor, :progress, :safety]`, public? true)
  - [ ] `daily_log_context` (:string, default the canonical seed text from CONTEXT.md, public? true)
  - [ ] `daily_log_min_accuracy` (:float, constraints `[min: 0.0, max: 1.0]`, default `0.7`,
        public? true)
- [ ] `:create` action `accept` list includes the three new attributes (all optional —
      defaults fire when omitted)
- [ ] New action `:update_daily_log_brief` accepts the three new attributes
- [ ] Policy for `:update_daily_log_brief` authorizes `:pm` and `:org_admin` only
- [ ] Migration adds the three columns with defaults; existing projects backfill to defaults
- [ ] `BriefFormComponent` LiveComponent renders section toggle checkboxes, context textarea
      (~1000 char limit shown in UI), and min-accuracy number input

### DailyLog Resource Extensions

- [ ] Status enum extended to
      `[:pending, :processing, :awaiting_clarification, :draft, :submitted, :failed]`
- [ ] New attributes:
  - [ ] `clarification_questions` ({:array, :map}, default `[]`)
  - [ ] `clarification_audio_key` (:string)
  - [ ] `clarification_audio_duration` (:integer)
  - [ ] `clarification_transcript` (:string)
  - [ ] `clarification_round` (:integer, default `0`)
- [ ] New actions:
  - [ ] `:request_clarification` — update; accepts `clarification_questions`; sets status
        `:awaiting_clarification`; restricted to `actor_absent()` and `:org_admin` (called
        from the reactor)
  - [ ] `:submit_clarification` — update; accepts `clarification_audio_key` and
        `clarification_audio_duration`; refuses (returns error) when
        `clarification_round >= 1`; sets status back to `:processing`; triggers
        `EnqueueClarification` change
  - [ ] `:apply_clarification_transcript` — update; accepts `clarification_transcript`;
        restricted to `actor_absent()` and `:org_admin`
  - [ ] `:skip_clarification` — update; sets status to `:processing`; triggers
        `EnqueueFinalize` change
- [ ] Policy: `:submit_clarification` and `:skip_clarification` are authorized for the log's
      foreman and for `:org_admin`
- [ ] `:apply_structure` is extended so it can also be invoked after `merge_clarification`
      (already permits internal callers via `actor_absent()`) and bumps
      `clarification_round` when called from the clarification reactor
- [ ] Migration applied via `mix ash.codegen` then `mix ash.migrate`

### Project-Aware Structuring

- [ ] `Sitevoice.Reporting.Steps.StructureWithClaude` loads the project (via `log.project_id`,
      with tenant) before the Claude call
- [ ] System prompt is rebuilt to include:
  - [ ] `PROJECT CONTEXT: {project.daily_log_context}`
  - [ ] `REQUIRED SECTIONS for this project: {project.required_sections}`
  - [ ] Instruction that `accuracy_score` should be lower when required sections lack
        coverage in the transcript

### Pipeline Split

- [ ] `Sitevoice.Reporting.Reactors.ProcessRecording` is trimmed to end at
      `assess_completeness`; everything from `caption_photos` onward moves to
      `FinalizeReport`
- [ ] After `save_structure`, the reactor runs `assess_completeness`:
  - [ ] On `{:ok, :complete}` — enqueues `FinalizeReportWorker` and returns
  - [ ] On `{:ok, {:incomplete, missing_sections}}` AND `clarification_round == 0` — runs
        `generate_clarifications` → `save_clarification_request` →
        `broadcast_clarification_needed`, then returns
  - [ ] On `{:ok, {:incomplete, _}}` AND `clarification_round >= 1` — enqueues
        `FinalizeReportWorker` (cap enforced)

### New Reactor Steps

- [ ] `AssessCompleteness` — pure step; loads the log's project (tenanted, authorize?: false);
      returns `:complete` unless any required section is empty/blank OR `accuracy_score <
      project.daily_log_min_accuracy`
- [ ] `GenerateClarifications` — calls Claude `claude-sonnet-4-20250514`, `max_tokens: 600`,
      `timeout: 15_000`; prompt includes project brief + transcript + extracted output +
      missing sections; expects JSON response `[{"question":"...","missing_field":"..."}]`;
      falls back to deterministic templates on Claude failure or invalid JSON
- [ ] `SaveClarificationRequest` — calls `:request_clarification` with the generated
      questions
- [ ] `BroadcastClarificationNeeded` — `Phoenix.PubSub.broadcast` to
      `"org:#{org_id}:log:#{log_id}"` with `{:clarification_needed, %{questions: [...]}}`
- [ ] `FetchClarificationAudio` — downloads `clarification_audio_key` via
      `Sitevoice.Storage`
- [ ] `TranscribeClarification` — Whisper call on the addendum (may reuse
      `TranscribeWhisper` with a tagged variant)
- [ ] `SaveClarificationTranscript` — calls `:apply_clarification_transcript`
- [ ] `MergeClarification` — Claude call with the project brief, original transcript,
      already-extracted structured fields, and clarification transcript; returns updated
      structured JSON; replaces fields wholesale on the next `:apply_structure`

### ProcessClarification Reactor

- [ ] `Sitevoice.Reporting.Reactors.ProcessClarification` exists with inputs `log_id` and
      `organization_id`
- [ ] Step order: `set_tenant` → `fetch_log` → `fetch_clarification_audio` →
      `transcribe_clarification` → `save_clarification_transcript` → `merge_clarification` →
      `save_structure` (via `:apply_structure`; bumps `clarification_round` to 1) →
      `enqueue_finalize`
- [ ] `compensate/4` on the final step calls `:mark_failed` and broadcasts
      `:pipeline_failed`

### FinalizeReport Reactor

- [ ] `Sitevoice.Reporting.Reactors.FinalizeReport` exists with inputs `log_id` and
      `organization_id`
- [ ] Step order: `set_tenant` → `fetch_log` → `caption_photos` → `broadcast_structured`
      → `generate_pdf` → `store_pdf` → `save_pdf_key` → `broadcast_pdf_generated` →
      `notify` (BroadcastReady)
- [ ] Reuses existing steps (`CaptionPhotos`, `GeneratePdf`, `StoreTigris`, `BroadcastReady`,
      `BroadcastPipelineStep`) — no duplication

### Oban Workers

- [ ] `Sitevoice.Workers.ClarificationProcessor` — queue `:audio`, `max_attempts: 3`;
      args `%{"log_id" => uuid, "organization_id" => uuid}`; sets tenant; runs
      `ProcessClarification`; on error calls `mark_failed` and broadcasts `:pipeline_failed`
- [ ] `Sitevoice.Workers.FinalizeReportWorker` — queue `:audio`, `max_attempts: 3`;
      args same as above; sets tenant; runs `FinalizeReport`; same failure behavior

### Phoenix Channels

- [ ] `SitevoiceWeb.RecordingChannel`:
  - [ ] `handle_info({:clarification_needed, payload}, socket)` pushes
        `"clarification_needed"` to the client
  - [ ] `handle_in("clarification_complete", %{"audio_key" => ak, "audio_duration" => d}, socket)`
        — verifies socket actor is the log's foreman; calls `:submit_clarification` (which
        enqueues the worker); pushes `"clarification_processing"`; replies `:ok`
  - [ ] `handle_in("skip_clarification", _, socket)` — verifies foreman; calls
        `:skip_clarification`; replies `:ok`
- [ ] `SitevoiceWeb.LogChannel` mirrors the `:clarification_needed` `handle_info`

### LiveView

- [ ] `SitevoiceWeb.Logs.ClarificationLive` at route `/logs/:id/clarify`
  - [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
  - [ ] `mount/3` loads the log (must be the foreman or an admin), assigns
        `:questions`, `:upload_config`
  - [ ] Renders a list of questions
  - [ ] Renders an audio upload (allow `.m4a/.mp3/.wav/.ogg`, max 50MB, same as `NewLive`)
  - [ ] "Skip" button → `phx-click="skip"` → calls `:skip_clarification` → navigates to
        `/logs/:id/processing`
  - [ ] On upload completion → stores to Tigris with key
        `{org_id}/audio/clarifications/{log_id}/{uuid}.m4a` → calls `:submit_clarification`
        → navigates to `/logs/:id/processing`
- [ ] `SitevoiceWeb.Logs.ProcessingLive` handles the channel event
      `clarification_needed` and `push_navigate` to `/logs/:id/clarify`
- [ ] `BriefFormComponent` is embedded in both project create and project edit/settings
      LiveViews
- [ ] Project edit route is added inside the authenticated scope; only PM/org_admin can reach it
      (Ash policy denial yields a flash + redirect)

### Tests

All tagged `@moduletag slice: :clarification`. Use `Req.Test` stubs for Claude and Whisper.

- [ ] `Project` resource: defaults, identity, `:update_daily_log_brief` policy
- [ ] `DailyLog` resource: new actions, cap enforcement on `:submit_clarification`
- [ ] `AssessCompleteness`: complete, incomplete-by-empty-section, incomplete-by-low-accuracy,
      cap-respected paths
- [ ] `GenerateClarifications`: Claude happy path + Claude failure → template fallback
- [ ] `MergeClarification`: Claude stub returns merged JSON; replaces fields
- [ ] `ProcessClarification` reactor: full integration with stubs
- [ ] `FinalizeReport` reactor: full integration with stubs (no behavioral regression)
- [ ] `ProcessRecording`: branching test — complete path enqueues `FinalizeReportWorker`;
      incomplete path broadcasts `:clarification_needed`
- [ ] `RecordingChannel`: `clarification_complete` and `skip_clarification` callbacks
- [ ] `ClarificationLive`: skip flow + submit flow

### Verification

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:clarification` — all tests pass
- [ ] `mix test` — no regressions in slices 00–13
- [ ] Manual smoke test in dev: hospital project with custom context produces hospital-flavored
      clarification questions when given a labor-less recording

## What This Slice Does NOT Include

- More than one clarification round (cap is hardcoded to 1)
- Text-mode clarification fallback (voice-only per user decision)
- Mobile (React Native) implementation — channel events are designed so Slice 10 can adopt
  them later without backend changes
- Letting Claude alone decide trigger logic without rules (rule-based is cheaper and
  predictable)
- Tuning thresholds via runtime config — held on the Project resource for v1
- Editing the clarification question text before answering (foreman just answers all in one
  recording)

## Key Behaviours

### Project Brief Default Seed

```
General construction site. Each daily log should describe crew composition by trade,
the day's work progress with locations, any safety incidents (or 'none'), notable
deliveries or equipment movements, and any delays. Note weather if it affected work.
```

### Project-Aware Structuring Prompt (sketch)

```
You are extracting a construction daily log for this project.

PROJECT CONTEXT:
{project.daily_log_context}

REQUIRED SECTIONS for this project: {Enum.join(project.required_sections, ", ")}

Extract from the transcript and return ONLY valid JSON with these keys:
labor, progress, equipment, materials, delays, safety, weather, accuracy_score.
Lower accuracy_score when the transcript does not adequately cover the REQUIRED SECTIONS.

(remaining schema as today)
```

### Completeness Rules

Any one of the following triggers a clarification round (unless `clarification_round >= 1`):

- `accuracy_score < project.daily_log_min_accuracy`
- Any section listed in `project.required_sections` is `[]` or blank in the extracted output

### Clarification Generation Prompt (sketch)

```
You help foremen fill gaps in daily-log voice memos for this project.

PROJECT CONTEXT: {project.daily_log_context}
MISSING SECTIONS: {missing_sections}
TRANSCRIPT: {transcript}
EXTRACTED SO FAR: {structured_json}

Produce 1–3 short, specific questions to ask the foreman, tailored to this project's context.
Return ONLY valid JSON: [{"question":"...","missing_field":"labor|progress|...|accuracy"}].
```

Deterministic fallback templates if the Claude call fails:

- missing `labor` → "How many crew members on site today and what trades?"
- missing `progress` → "What work was completed today?"
- missing `safety` → "Were there any safety incidents or near-misses? Say 'none' if not."
- low `accuracy_score` → "Can you briefly summarize the key activities for the day?"

### Channel Events

```
# Server → client
push "clarification_needed", %{questions: [%{question, missing_field}, ...]}
push "clarification_processing", %{}
push "pipeline_update", %{step: "...", status: :complete}   # existing
push "report_ready", %{...}                                 # existing
push "pipeline_failed", %{...}                              # existing

# Client → server
handle_in "recording_complete", %{...}      # existing
handle_in "clarification_complete", %{audio_key, audio_duration}
handle_in "skip_clarification", %{}
```

### Tenant Rules

- `set_tenant` is the first step of every new reactor
- Every Ash call from within new workers and steps uses `tenant: organization_id,
  authorize?: false`
- Channel handlers re-apply tenant via `Ash.PlugHelpers.set_tenant(socket, org_id)` on each
  `handle_in`
- PubSub topics: `"org:{org_id}:log:{log_id}"` (already used; reused for the new event)

### Storage Key Conventions

- Daily log audio (existing): `{org_id}/audio/{project_id}/{uuid}-{filename}.m4a`
- Clarification audio (new): `{org_id}/audio/clarifications/{log_id}/{uuid}.m4a`
- PDF (existing, unchanged): `{org_id}/pdfs/...`
