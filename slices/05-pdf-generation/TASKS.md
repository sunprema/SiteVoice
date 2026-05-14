# Tasks — Slice 05: PDF Generation

Work through in order. Check off each task as it is completed.

---

## 1. Create Typst Template

File: `priv/templates/daily_log.typ`

- [x] Add `#set document(...)` with title `"Daily Log — " + sys.inputs.elixir_data.date`
- [x] Add `#set page(paper: "us-letter", margin: (x: 1.2in, y: 1in))`
- [x] Add `#set text(font: "Barlow", size: 10pt)`
- [x] Header grid: project name (h1), date, org, project_code on left; foreman + submitted_at on right
- [x] Section divider `#line(length: 100%)`
- [x] `== Labor` section: `#for e in sys.inputs.elixir_data.labor` — crew, headcount, trade, hours
- [x] `== Progress` section: `#for e in sys.inputs.elixir_data.progress` — description, location
- [x] `== Equipment` section: `#for e in sys.inputs.elixir_data.equipment` — item, status, note (optional)
- [x] `== Materials` section: `#for e in sys.inputs.elixir_data.materials` — item, quantity, received_at
- [x] `== Delays` section: `#for e in sys.inputs.elixir_data.delays` — description, impact
- [x] `== Safety` section: `#for e in sys.inputs.elixir_data.safety` — description
- [x] `== Photos` section: grid of photo thumbnails (if photos list is non-empty), caption below each
- [x] Accuracy score line: `AI Accuracy Score: X%` (only when accuracy_score is non-nil)
- [x] Footer: `#line(length: 100%, stroke: 0.5pt)` then 8pt gray text `SiteVoice AI · PDF/A-3a · {log_id}`

## 2. Implement GeneratePdf Step

File: `lib/sitevoice/reporting/steps/generate_pdf.ex`

- [x] Replace stub body with real implementation
- [x] `run/3` matches `%{log: log}` — reads template, builds string-keyed data map, calls Imprintor
- [x] Add private `format_dt/1` with two clauses: `nil` → `"—"`, datetime → formatted string
- [x] Remove the single-line stub comment
- [x] `compensate/4` returns `:ok` (unchanged)

## 3. Fix StoreTigris Step

File: `lib/sitevoice/reporting/steps/store_tigris.ex`

- [x] Add `:project_id` to the matched argument map in the non-empty-binary `run/3` clause
- [x] Fix `pdf_key` call: `Sitevoice.Storage.pdf_key(org_id, project_id, log_id)` (three distinct vars)
- [x] Include `:key` in the returned result map: `{:ok, %{url: url, key: key}}`
- [x] The empty-binary guard clause returns `{:ok, %{url: nil, key: nil}}` for consistency
- [x] `compensate/4` returns `:ok` (unchanged)

## 4. Add update_pdf Action to DailyLog

File: `lib/sitevoice/reporting/daily_log.ex`

- [x] Add `update :update_pdf` action accepting `[:pdf_key]`
- [x] Add policy for `:update_pdf` allowing `actor_absent()` and `org_admin`

## 5. Update ProcessRecording Reactor

File: `lib/sitevoice/reporting/reactors/process_recording.ex`

- [x] Update `fetch_log` step (FetchLog module) to load `[:organization, :project, :foreman, :photos]`
- [x] Add `argument :project_id, result(:fetch_log, [:project_id])` to the `store_pdf` step
- [x] Add `update :save_pdf_key` step after `store_pdf` with `wait_for :store_pdf`
- [x] `notify` step unchanged

## 6. Write GeneratePdf Tests

File: `test/sitevoice/reporting/steps/generate_pdf_test.exs`

- [x] Tag `@moduletag slice: :pdf_generation`
- [x] Create `Sitevoice.Test.ImprintorStub` in `test/support/imprintor_stub.ex`
- [x] Happy path tests: returns binary, data map has string keys, all six categories present
- [x] Error path test: stub returns error, run/3 returns `{:error, "PDF failed: ..."}`

## 7. Write Integration Test

File: `test/sitevoice/reporting/reactors/process_recording_pdf_test.exs`

- [x] Tag `@moduletag slice: :pdf_generation`
- [x] Happy path: `DailyLog.pdf_key` is non-nil after pipeline completes
- [x] Verify status remains `:draft` and structured data is preserved
- [x] Error path: Imprintor failure causes Reactor to return `{:error, _}`

## 8. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:pdf_generation` — all tests pass
- [x] `mix test` — no regressions in slices 00–04
