# Context — Slice 05: PDF Generation

## Dependency

Slice 04 (AI Pipeline) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §13.1 — Imprintor (Typst + Rust) — `GeneratePdf` step implementation
2. `docs/APPLICATION_SPEC.md` §13.2 — Typst Template (`priv/templates/daily_log.typ`)
3. `docs/APPLICATION_SPEC.md` §12.2 — Org-Prefixed Key Structure (PDF key format)
4. `docs/APPLICATION_SPEC.md` §12.3 — Storage Module (`pdf_key/3`, `store_pdf/2`, `presigned_url/3`)
5. `docs/APPLICATION_SPEC.md` §9.3 — Ash Reactor: Full Pipeline Definition (step wiring)
6. `docs/DOMAIN_MODEL.md` §5 — DailyLog `:edit_draft` and `pdf_key` attribute; `PdfUrl` calculation
7. `docs/DOMAIN_MODEL.md` §9 — Calculations Reference (`PdfUrl`)
8. `docs/CODING_STANDARDS.md` — Reactor step conventions
9. `CLAUDE.md` — Architecture Rules §Reactor, §Multitenancy, §Oban

## Existing Files To Modify

These files already exist and will be modified:

- `lib/sitevoice/reporting/steps/generate_pdf.ex` — replace stub `{:ok, <<>>}` with real Imprintor call
- `lib/sitevoice/reporting/steps/store_tigris.ex` — fix `pdf_key/3` bug (passes `org_id` twice instead of `project_id`; step must receive `project_id` argument from Reactor)
- `lib/sitevoice/reporting/reactors/process_recording.ex` — add `ash_update :save_pdf_key` step between `store_pdf` and `notify`; wire `project_id` argument to `store_pdf`; ensure `FetchLog` loads `:organization` and `:project` associations needed by `GeneratePdf`
- `lib/sitevoice/reporting/daily_log.ex` — add `update :update_pdf` action accepting `[:pdf_key]`; add `authorize_if actor_absent()` policy for `:update_pdf`

## New Files To Create

### Template
- `priv/templates/daily_log.typ` — Typst template (PDF/A-3a, all 6 category sections, photos, accuracy score)

### Tests
- `test/sitevoice/reporting/steps/generate_pdf_test.exs`
- `test/sitevoice/reporting/reactors/process_recording_pdf_test.exs` — integration test for the full pipeline now producing a real PDF binary

## Key Constraints

- Module names use `Sitevoice` (lowercase v) — the project uses this convention, not `SiteVoice`
- Imprintor is already a dependency (`{:imprintor, "~> 0.1.0"}` in `mix.exs`) — no new deps needed
- Template must be read with `File.read!(Application.app_dir(:sitevoice, "priv/templates/daily_log.typ"))`
- `Imprintor.Config.new(template, data, pdf_standard: "a-3a")` — always use `"a-3a"` standard
- `data` map must use **string keys** (not atom keys) for Imprintor compatibility
- `StoreTigris` receives `:project_id` argument from the Reactor (add this argument to the step and the Reactor wiring)
- `StoreTigris` key generation: `Sitevoice.Storage.pdf_key(org_id, project_id, log_id)` — three distinct arguments
- `DailyLog.:update_pdf` is a system-only action — policy must allow `actor_absent()`; never accept `organization_id` from input
- The `ash_update :save_pdf_key` step in the Reactor must `wait_for :store_pdf`
- `FetchLog` step (or the Reactor's `fetch_log` step) must load `[:organization, :project, :foreman, :photos]` so `GeneratePdf` has all required fields
- All tests tagged `@moduletag slice: :pdf_generation`
- No real Imprintor call in tests — stub `Imprintor.compile_to_pdf/1` using `Mox` or return a fixed binary
- `mix compile --warnings-as-errors` — zero warnings
