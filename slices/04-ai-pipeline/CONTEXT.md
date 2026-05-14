# Context — Slice 04: AI Pipeline

## Dependency

Slice 03 (Recording) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §9.3 — Ash Reactor: Full Pipeline Definition
2. `docs/APPLICATION_SPEC.md` §10.1 — Transcription: OpenAI Whisper API
3. `docs/APPLICATION_SPEC.md` §10.2 — Structuring: Anthropic Claude API
4. `docs/APPLICATION_SPEC.md` §10.3 — Photo Captioning: Claude Vision
5. `docs/APPLICATION_SPEC.md` §6.5 — Oban Jobs: Tenant Propagation
6. `docs/APPLICATION_SPEC.md` §6.6 — Ash Reactor: Tenant Propagation
7. `docs/APPLICATION_SPEC.md` §6.8 — PubSub: Org-Namespaced Topics
8. `docs/DOMAIN_MODEL.md` §5 — DailyLog `:apply_transcript`, `:apply_structure`, `:mark_failed` actions
9. `docs/CODING_STANDARDS.md` — Reactor step conventions
10. `CLAUDE.md` — Architecture Rules §Reactor, §Oban, §Multitenancy

## Existing Files To Load

These files already exist and will be modified:

- `lib/sitevoice/workers/audio_processor.ex` — update `perform/1` to call the Reactor (currently a stub)
- `lib/sitevoice/reporting/daily_log.ex` — verify `:apply_transcript`, `:apply_structure`, `:mark_failed` actions are present and correct
- `lib/sitevoice/reporting/photo.ex` — verify `:apply_caption` action exists (nil actor allowed)

## New Files To Create

### Reactor

- `lib/sitevoice/reporting/reactors/process_recording.ex`

### Reactor Steps

- `lib/sitevoice/reporting/steps/set_tenant.ex`
- `lib/sitevoice/reporting/steps/fetch_log.ex`
- `lib/sitevoice/reporting/steps/fetch_from_tigris.ex`
- `lib/sitevoice/reporting/steps/transcribe_whisper.ex`
- `lib/sitevoice/reporting/steps/structure_with_claude.ex`
- `lib/sitevoice/reporting/steps/caption_photos.ex`
- `lib/sitevoice/reporting/steps/broadcast_ready.ex`
- `lib/sitevoice/reporting/steps/generate_pdf.ex` — **stub** (Slice 05 implements for real)
- `lib/sitevoice/reporting/steps/store_tigris.ex`

### Tests

- `test/sitevoice/reporting/reactors/process_recording_test.exs`
- `test/sitevoice/reporting/steps/transcribe_whisper_test.exs`
- `test/sitevoice/reporting/steps/structure_with_claude_test.exs`
- `test/sitevoice/reporting/steps/caption_photos_test.exs`

## Key Constraints

- Module names use `Sitevoice` (lowercase v) — the project uses this convention, not `SiteVoice`
- Every Reactor step file goes in `lib/sitevoice/reporting/steps/`
- `SetTenant` step must always `wait_for` before any Ash steps run — `FetchLog` has `wait_for :set_tenant`
- `AudioProcessor.perform/1` must call `Ash.Query.set_tenant(org_id)` as its very first line
- External API steps (`TranscribeWhisper`, `StructureWithClaude`, `CaptionPhotos`) must have timeouts
- Steps that mutate state must implement `compensate/4` — `SaveTranscript`, `SaveStructure` compensate by resetting status
- `async?: true` only on steps with no dependency on other concurrent steps — `StructureWithClaude` and `CaptionPhotos` can run concurrently after transcription
- Never call Oban from inside a Reactor step
- All external API calls use `Req` — never `:httpoison`, `:tesla`, or `:httpc`
- API keys fetched with `Application.fetch_env!/2` — never hardcoded
- `GeneratePdf` step in this slice returns `{:ok, <<>>}` stub (real implementation in Slice 05)
- `StoreTigris` step: if PDF binary is empty stub, skip the upload and return `{:ok, %{url: nil}}`
- `BroadcastReady` broadcasts to `"org:#{org_id}:log:#{log_id}"` topic — never a bare topic
- `CaptionPhotos` then calls `Photo.:apply_caption` action with `actor: nil` (Reactor context, no user)
- All Req.Test stubs used in tests — no real API calls in test env
- All tests tagged `@moduletag slice: :ai_pipeline`
