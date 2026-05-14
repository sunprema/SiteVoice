# Slice 05 — PDF Generation

**Goal:** Replace the `GeneratePdf` stub with a real Imprintor call, create the Typst template,
fix the `StoreTigris` `pdf_key` bug, persist the PDF key to `DailyLog`, and add tests confirming
the full pipeline produces a valid PDF binary stored to Tigris with the key saved on the record.

## Acceptance Criteria

- [ ] `priv/templates/daily_log.typ` exists and renders all six category sections (labor, progress,
      equipment, materials, delays, safety), photos, accuracy score, organization, project, foreman,
      date, and submitted_at — styled for US Letter, font Barlow, PDF/A-3a
- [ ] `Sitevoice.Steps.GeneratePdf.run/3` reads the Typst template from
      `Application.app_dir(:sitevoice, "priv/templates/daily_log.typ")`, builds a string-keyed
      data map from the log struct, calls `Imprintor.Config.new/3` with `pdf_standard: "a-3a"`,
      calls `Imprintor.compile_to_pdf/1`, returns `{:ok, binary}` or `{:error, "PDF failed: ..."}`
- [ ] `Sitevoice.Steps.StoreTigris.run/3` receives `%{binary:, key: log_id, organization_id:,
      project_id:}` and calls `Sitevoice.Storage.pdf_key(org_id, project_id, log_id)` — three
      distinct arguments (no longer passing `org_id` twice)
- [ ] `Sitevoice.Reporting.DailyLog` has `update :update_pdf` action accepting `[:pdf_key]`,
      policy allows `actor_absent()`, action does NOT set status (pdf arrives after `:draft`)
- [ ] `Sitevoice.Reporting.Reactors.ProcessRecording` is updated:
      - `fetch_log` step loads `[:organization, :project, :foreman, :photos]`
      - `store_pdf` step receives a `:project_id` argument sourced from `result(:fetch_log, [:project_id])`
      - New `ash_update :save_pdf_key` step runs `DailyLog.:update_pdf`, inputs `%{pdf_key: result(:store_pdf, [:key])}`, filter `id == ^input(:log_id)`, `wait_for :store_pdf`
      - `notify` step is unchanged but implicitly runs after `save_pdf_key` completes (Reactor sequentializes via argument dependency)
- [ ] `DailyLog.pdf_key` is populated after the pipeline completes successfully
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:pdf_generation` — all tests pass
- [ ] `mix test` — no regressions in slices 00–04

## What This Slice Does NOT Include

- Email of the PDF to the Project Manager (Slice 07)
- Phoenix Channel `pipeline_update` broadcasts per step (Slice 06)
- Procore integration dispatch (Slice 08)
- Mobile PDF preview screen (Slice 09)

## Key Behaviors

### Imprintor Data Map

`GeneratePdf` converts the log struct to a string-keyed map. Photos are included as a list of
maps with `"url"`, `"caption"`, and `"category"` keys. Nested arrays (labor, progress, etc.) are
passed as-is since they are already `{:array, :map}` attributes. `format_dt/1` converts
`submitted_at` to `"Month DD, YYYY HH:MM"` or `"—"` when nil.

### StoreTigris Bug Fix

The existing step passes `org_id` as both the first and second argument to `pdf_key/3`. The
correct call is `Sitevoice.Storage.pdf_key(org_id, project_id, log_id)`. The Reactor must be
updated to pass `project_id` as an argument to the `store_pdf` step (sourced from
`result(:fetch_log, [:project_id])`).

### save_pdf_key Step

After `store_pdf` returns `{:ok, %{url: presigned_url, key: storage_key}}`, the Reactor runs
`ash_update :save_pdf_key` to persist the `pdf_key` (storage key, not the presigned URL) to the
`DailyLog` record. `StoreTigris` must return both `:url` and `:key` in its result map so the
Reactor can reference each independently.

### Typst Template Structure

The template uses `sys.inputs.elixir_data` to access all fields. Arrays are iterated with `#for`.
Photos are rendered as a grid of thumbnails with their captions below. The footer line shows
`SiteVoice AI · PDF/A-3a · {log_id}`. No hardcoded values — all content comes from `data`.

### Test Strategy

- `generate_pdf_test.exs`: mock `Imprintor.compile_to_pdf/1` via `Mox` to return a fixed binary;
  verify the data map is correctly shaped (string keys, all six categories present)
- `process_recording_pdf_test.exs`: integration test that stubs Whisper, Claude, Tigris, and
  Imprintor; asserts `DailyLog.pdf_key` is set after the Reactor completes
