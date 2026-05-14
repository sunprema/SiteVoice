# Tasks — Slice 04: AI Pipeline

Work through in order. Check off each task as it is completed.

---

## 1. Create SetTenant Step

File: `lib/sitevoice/reporting/steps/set_tenant.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{organization_id: org_id}`, calls `Ash.set_tenant(org_id)`, returns `{:ok, org_id}`
- [x] `compensate/4` returns `:ok`

## 2. Create FetchLog Step

File: `lib/sitevoice/reporting/steps/fetch_log.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{log_id: log_id}`, reads `DailyLog` by id via `Ash.get!` loading `:photos` and `:foreman`
- [x] Returns `{:ok, log}` or `{:error, reason}`
- [x] `compensate/4` returns `:ok`

## 3. Create FetchFromTigris Step

File: `lib/sitevoice/reporting/steps/fetch_from_tigris.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{key: key}`, calls `Sitevoice.Storage.fetch(key)`
- [x] Returns `{:ok, binary}` or `{:error, reason}`
- [x] `compensate/4` returns `:ok`

## 4. Create TranscribeWhisper Step

File: `lib/sitevoice/reporting/steps/transcribe_whisper.ex`

- [x] `use Reactor.Step`
- [x] Define `@construction_prompt` module attribute with construction-domain hint text (see §10.1)
- [x] `run/3` matches `%{audio: binary, language: lang}`:
  - Maps `:es` → `"es"`, anything else → `"en"`
  - POSTs to `https://api.openai.com/v1/audio/transcriptions` using `Req.post/2`
  - Sets `receive_timeout: 60_000` in Req options
  - Uses `form_multipart:` with `file:`, `model: "whisper-1"`, `language:`, `prompt:`, `response_format: "json"`
  - On `%{status: 200, body: %{"text" => text}}` returns `{:ok, text}`
  - On other status returns `{:error, "Whisper #{s}: #{inspect(b)}"}`
- [x] `api_key/0` private function uses `Application.fetch_env!(:sitevoice, :openai_api_key)`
- [x] `compensate/4` returns `:ok`

## 5. Create StructureWithClaude Step

File: `lib/sitevoice/reporting/steps/structure_with_claude.ex`

- [x] `use Reactor.Step`
- [x] Define `@system_prompt` module attribute (see §10.2 for exact content)
- [x] `run/3` matches `%{transcript: transcript}`:
  - POSTs to `https://api.anthropic.com/v1/messages` using `Req.post/2`
  - Sets `receive_timeout: 30_000`
  - Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
  - JSON body: `model: "claude-sonnet-4-20250514"`, `max_tokens: 2000`, `system:`, `messages:`
  - Parses JSON response, converts string keys to atom keys
  - Returns `{:ok, map}` or `{:error, reason}`
- [x] `api_key/0` private function uses `Application.fetch_env!(:sitevoice, :anthropic_api_key)`
- [x] `compensate/4` returns `:ok`

## 6. Create CaptionPhotos Step

File: `lib/sitevoice/reporting/steps/caption_photos.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{photo_keys: photos, transcript: transcript}` where `photos` is list of `Photo` structs
- [x] For each photo:
  - Fetch binary: `Sitevoice.Storage.fetch(photo.storage_key)`
  - Base64-encode the binary
  - Call `generate_caption/2` using Claude Vision API (model: `claude-sonnet-4-20250514`, max_tokens: 100)
  - Call `infer_category/1` using regex patterns (delays, equipment, safety, materials, progress)
  - Update photo record: `Ash.update!(photo, :apply_caption, %{caption: caption, category: category}, actor: nil)`
- [x] Returns `{:ok, updated_photos}`
- [x] `api_key/0` private function uses `Application.fetch_env!(:sitevoice, :anthropic_api_key)`
- [x] `compensate/4` returns `:ok`

## 7. Create GeneratePdf Step (Stub)

File: `lib/sitevoice/reporting/steps/generate_pdf.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{log: _log}`, returns `{:ok, <<>>}`
- [x] Add a single-line comment: `# Implemented in Slice 05 when Imprintor integration exists`
- [x] `compensate/4` returns `:ok`

## 8. Create StoreTigris Step

File: `lib/sitevoice/reporting/steps/store_tigris.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{binary: binary, key: log_id, organization_id: org_id}`:
  - If `binary == <<>>` (stub), return `{:ok, %{url: nil}}` (skip upload)
  - Otherwise: generate PDF key via `Sitevoice.Storage.pdf_key(org_id, log.project_id, log_id)`,
    call `Sitevoice.Storage.store_pdf/2`, then `Sitevoice.Storage.presigned_url/3`
  - Return `{:ok, %{url: url}}`
- [x] `compensate/4` returns `:ok`

## 9. Create BroadcastReady Step

File: `lib/sitevoice/reporting/steps/broadcast_ready.ex`

- [x] `use Reactor.Step`
- [x] `run/3` matches `%{log_id: log_id, organization_id: org_id, pdf_url: url}`:
  - Calls `Phoenix.PubSub.broadcast(Sitevoice.PubSub, "org:#{org_id}:log:#{log_id}", {:report_ready, %{log_id: log_id, pdf_url: url}})`
  - Returns `{:ok, :sent}`
- [x] `compensate/4` returns `:ok`

## 10. Create ProcessRecording Reactor

File: `lib/sitevoice/reporting/reactors/process_recording.ex`

- [x] `use Ash.Reactor`
- [x] Declare `input :log_id` and `input :organization_id`
- [x] Wire all steps in order per §9.3:
  1. `step :set_tenant, Sitevoice.Steps.SetTenant` — argument `:organization_id`
  2. `step :fetch_log, Sitevoice.Steps.FetchLog` — argument `:log_id`, `wait_for :set_tenant`
  3. `step :fetch_audio, Sitevoice.Steps.FetchFromTigris` — argument `:key` from `result(:fetch_log, [:audio_key])`
  4. `step :transcribe, Sitevoice.Steps.TranscribeWhisper` — arguments `:audio` and `:language` (from foreman's `preferred_language`)
  5. `ash_update :save_transcript, Sitevoice.Reporting.DailyLog` — inputs `%{transcript: result(:transcribe)}`, action `:apply_transcript`, filter by log_id
  6. `step :structure, Sitevoice.Steps.StructureWithClaude` — argument `:transcript`, `async?: true`
  7. `step :caption_photos, Sitevoice.Steps.CaptionPhotos` — arguments `:photo_keys` (log's photos) and `:transcript`, `async?: true`
  8. `ash_update :save_structure, Sitevoice.Reporting.DailyLog` — inputs all structured fields, action `:apply_structure`, filter by log_id
  9. `step :generate_pdf, Sitevoice.Steps.GeneratePdf` — argument `:log` from `result(:save_structure)`
  10. `step :store_pdf, Sitevoice.Steps.StoreTigris` — arguments `:binary`, `:key`, `:organization_id`
  11. `step :notify, Sitevoice.Steps.BroadcastReady` — arguments `:log_id`, `:organization_id`, `:pdf_url`
- [x] Add `compensate :save_transcript` block that resets DailyLog status to `:pending`
- [x] Add `compensate :save_structure` block that resets DailyLog status to `:processing`

## 11. Update AudioProcessor Worker

File: `lib/sitevoice/workers/audio_processor.ex`

- [x] `perform/1` first line: `Ash.set_tenant(org_id)` (not just assigned to `_tenant`)
- [x] Calls `Sitevoice.Reporting.Reactors.ProcessRecording.run(%{log_id: log_id, organization_id: org_id})`
- [x] On `{:ok, _}` returns `:ok`
- [x] On `{:error, reason}` calls `DailyLog.:mark_failed` action via Ash, then returns `{:error, reason}`

## 12. Verify DailyLog Actions

File: `lib/sitevoice/reporting/daily_log.ex`

- [x] Confirm `:apply_transcript` action accepts `[:transcript]` and sets `status: :processing`
- [x] Confirm `:apply_structure` action accepts all structured fields and sets `status: :draft`
- [x] Confirm `:mark_failed` action sets `status: :failed`
- [x] Confirm policies allow `actor_is_nil()` for `:apply_transcript`, `:apply_structure`, `:mark_failed`

## 13. Verify Photo `:apply_caption` Action

File: `lib/sitevoice/reporting/photo.ex`

- [x] Confirm `:apply_caption` action accepts `[:caption, :category]`
- [x] Confirm policy allows `actor_is_nil()` for `:apply_caption` (Reactor context)

## 14. Tests

All tests tagged `@moduletag slice: :ai_pipeline`. Use `Req.Test` stubs — never real endpoints.

File: `test/sitevoice/reporting/reactors/process_recording_test.exs`
- [x] Integration test: stubs Whisper and Claude APIs, runs full Reactor, asserts DailyLog status becomes `:draft`
- [x] Integration test: Whisper API returns error, asserts DailyLog status becomes `:failed`

File: `test/sitevoice/reporting/steps/transcribe_whisper_test.exs`
- [x] Happy path: stub returns `%{status: 200, body: %{"text" => "transcript"}}`, assert `{:ok, "transcript"}`
- [x] Error path: stub returns `%{status: 500}`, assert `{:error, _}`

File: `test/sitevoice/reporting/steps/structure_with_claude_test.exs`
- [x] Happy path: stub returns valid JSON response, assert `{:ok, %{labor: _, accuracy_score: _}}`
- [x] Error path: stub returns non-JSON body, assert `{:error, _}`

File: `test/sitevoice/reporting/steps/caption_photos_test.exs`
- [x] Happy path: stub returns a caption, assert photo record updated with caption and category

## 15. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:ai_pipeline` — all tests pass
- [x] `mix test` — no regressions in slices 00–03
