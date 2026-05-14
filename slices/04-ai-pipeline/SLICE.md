# Slice 04 — AI Pipeline

**Goal:** Wire the full AI processing pipeline: `ProcessRecording` Ash Reactor with all steps
(SetTenant, FetchLog, FetchFromTigris, TranscribeWhisper, StructureWithClaude, CaptionPhotos,
SaveTranscript, SaveStructure, BroadcastReady), `AudioProcessor` Oban worker calling the Reactor,
and `BroadcastReady` step broadcasting `report_ready` over org-namespaced PubSub.
`GeneratePdf` and `StoreTigris` are stubbed here — implemented for real in Slice 05.

## Acceptance Criteria

- [ ] `Sitevoice.Reporting.Reactors.ProcessRecording` exists and uses `Ash.Reactor`
- [ ] Reactor declares two inputs: `:log_id` and `:organization_id`
- [ ] Reactor step order matches the spec (§9.3): set_tenant → fetch_log → fetch_audio →
      transcribe → (structure + caption_photos concurrently) → save_structure → generate_pdf →
      store_pdf → notify
- [ ] `Sitevoice.Steps.SetTenant` step: calls `Ash.Query.set_tenant(org_id)`, returns `{:ok, org_id}`,
      implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.FetchLog` step: fetches `DailyLog` by `log_id` via Ash read,
      has `wait_for :set_tenant`, implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.FetchFromTigris` step: calls `Sitevoice.Storage.fetch/1` with the audio key,
      implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.TranscribeWhisper` step: POSTs multipart to OpenAI Whisper API using `Req`,
      uses `@construction_prompt`, respects `preferred_language` field, has a 60-second timeout,
      implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.StructureWithClaude` step: POSTs to Anthropic Messages API using `Req`,
      returns parsed map with atom keys, has a 30-second timeout, `async?: true` in Reactor,
      implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.CaptionPhotos` step: fetches each photo from Tigris, calls Claude Vision,
      infers category from caption text, `async?: true` in Reactor, updates `Photo` records via
      `Photo.:apply_caption` action with `actor: nil`, implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.GeneratePdf` step: **stub** — returns `{:ok, <<>>}` (Slice 05 implements),
      implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.StoreTigris` step: if binary is `<<>>` (stub), returns `{:ok, %{url: nil}}`;
      otherwise stores to Tigris and returns presigned URL, implements `compensate/4` returning `:ok`
- [ ] `Sitevoice.Steps.BroadcastReady` step: broadcasts `{:report_ready, %{log_id, pdf_url}}`
      to `"org:#{org_id}:log:#{log_id}"` via `Phoenix.PubSub.broadcast/3`, implements
      `compensate/4` returning `:ok`
- [ ] `ash_update :save_transcript` Reactor step: calls `DailyLog.:apply_transcript` with
      `%{transcript: result(:transcribe)}`; compensate resets status back to `:pending`
- [ ] `ash_update :save_structure` Reactor step: calls `DailyLog.:apply_structure` with all
      structured fields; compensate resets status back to `:processing`
- [ ] `Sitevoice.Workers.AudioProcessor.perform/1`: first line is `Ash.Query.set_tenant(org_id)`,
      calls `ProcessRecording.run(%{log_id: log_id, organization_id: org_id})`, returns `:ok`
      on success, `{:error, e}` on failure (enabling Oban retry)
- [ ] All external HTTP calls use `Req` with explicit timeouts
- [ ] No Oban calls from inside any Reactor step
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] All AI pipeline tests pass (`mix test --only slice:ai_pipeline`)
- [ ] `mix test` — no regressions in slices 00–03

## What This Slice Does NOT Include

- Real PDF generation (Slice 05) — `GeneratePdf` is a stub returning `<<>>`
- Full Phoenix Channel pipeline broadcasts with `pipeline_update` events (Slice 06)
- Email notifications on report ready (Slice 07)
- Procore integration dispatch (Slice 08)

## Key Behaviors

### Reactor Step Concurrency

`StructureWithClaude` and `CaptionPhotos` both depend on `result(:transcribe)` but not on each
other — both use `async?: true` and run in parallel. `SaveStructure` waits for both to complete
(it takes `result(:structure, ...)` so Reactor sequentializes automatically).

### Reactor Compensation

If `save_transcript` fails or a later step fails, `compensate :save_transcript` resets
`DailyLog.status` back to `:pending`. If `save_structure` fails, it resets back to `:processing`.
The `mark_failed` action on DailyLog should be called manually in the `AudioProcessor` worker's
error branch when the Reactor returns `{:error, _}`.

### CaptionPhotos Step

1. Fetch photo records from the log's `:photos` association (already loaded by `FetchLog`)
2. For each photo: `Sitevoice.Storage.fetch(photo.storage_key)` → Base64-encode → Claude Vision API
3. Infer category from caption using regex patterns
4. Call `Ash.update!(photo, :apply_caption, %{caption: caption, category: category}, actor: nil)`

### TranscribeWhisper Bilingual Support

If `foreman.preferred_language == :es`, pass `language: "es"` to Whisper. Claude's system prompt
outputs English regardless, so translation is transparent.

### BroadcastReady

After storing the PDF, broadcasts on `"org:#{org_id}:log:#{log_id}"`. In this slice, the Channel
handler (LogChannel) will subscribe and push to the socket — that is implemented in Slice 06.
The broadcast fires regardless; the socket subscription is wired later.

### AudioProcessor Error Handling

When the Reactor returns `{:error, reason}`, the worker should:

1. Call `DailyLog.:mark_failed` action via Ash (with tenant already set)
2. Return `{:error, reason}` to let Oban retry up to `max_attempts: 3`
