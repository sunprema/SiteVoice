# Tasks — Slice 03: Recording

Work through in order. Check off each task as it is completed.

---

## 1. Create the Reporting Domain Module

File: `lib/sitevoice/reporting.ex`

- [x] Define `SiteVoice.Reporting` with `use Ash.Domain`
- [x] List both resources: `SiteVoice.Reporting.DailyLog` and `SiteVoice.Reporting.Photo`
- [x] Add domain to `ash_domains` in `config/config.exs`

## 2. Create EnqueueProcessing Change

File: `lib/sitevoice/reporting/changes/enqueue_processing.ex`

- [x] Implement `Ash.Resource.Change` behaviour
- [x] Use `Ash.Changeset.after_action/2` so job is only inserted after the row commits
- [x] Job args: `%{log_id: log.id, organization_id: log.organization_id}`
- [x] Insert via `SiteVoice.Workers.AudioProcessor.new() |> Oban.insert!()`
- [x] Return `{:ok, log}` from the after_action callback

## 3. Create DispatchIntegrations Change (stub)

File: `lib/sitevoice/reporting/changes/dispatch_integrations.ex`

- [x] Implement `Ash.Resource.Change` behaviour
- [x] `change/3` wraps an `after_action` that returns `{:ok, log}` immediately
- [x] Add a single-line comment: `# Implemented in Slice 08 when Integrations domain exists`

## 4. Create Reporting Calculations

Files:

- `lib/sitevoice/reporting/calculations/pdf_url.ex`
- `lib/sitevoice/reporting/calculations/audio_url.ex`
- `lib/sitevoice/reporting/calculations/is_late.ex`
- `lib/sitevoice/reporting/calculations/photo_url.ex`

- [x] `PdfUrl.calculate/3` — maps records: if `pdf_key` is nil return nil, else call
      `SiteVoice.Storage.presigned_url("sitevoice-pdfs", key, 3600)` and unwrap `{:ok, url}`
- [x] `AudioUrl.calculate/3` — same pattern using `audio_key` and `"sitevoice-audio"` bucket
- [x] `PhotoUrl.calculate/3` — same pattern using `storage_key` and `"sitevoice-photos"` bucket
- [x] `IsLate.calculate/3` — returns `true` if `record.submitted_at` is not nil and its hour >= 18
      (compare `DateTime.to_time(submitted_at).hour >= 18`); returns `false` otherwise
- [x] All four return `{:ok, list}` wrapping the mapped values

## 5. Create AudioProcessor Oban Worker

File: `lib/sitevoice/workers/audio_processor.ex`

- [x] `use Oban.Worker, queue: :audio, max_attempts: 3`
- [x] `perform/1` matches `%Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}`

# pass tenant to every Ash call

- [x] For now, log the intent and return `:ok` (Reactor does not exist until Slice 04)

## 6. Create DailyLog Resource

File: `lib/sitevoice/reporting/daily_log.ex`

- [x] `use Ash.Resource` with `domain: SiteVoice.Reporting`, `data_layer: AshPostgres.DataLayer`,
      `extensions: [AshJsonApi.Resource, AshPaperTrail.Resource]`
- [x] Add `multitenancy do strategy :attribute; attribute :organization_id end` block
- [x] Add `postgres` block with table and all custom indexes
- [x] Add all attributes
- [x] Add identity: `:unique_log_per_day`
- [x] Add relationships
- [x] Add calculations
- [x] Add all actions
- [x] Add policies per policy matrix
- [x] Add `paper_trail do store_action_name? true; attributes_as_attributes [:organization_id] end`
- [x] Add `json_api do` block with all routes

## 7. Create Photo Resource

File: `lib/sitevoice/reporting/photo.ex`

- [x] Full resource with multitenancy, postgres, attributes, relationships, calculations, actions, policies, json_api

## 8. Update Project Resource

File: `lib/sitevoice/projects/project.ex`

- [x] Add `has_many :daily_logs, SiteVoice.Reporting.DailyLog`

## 9. Implement Real Stub Calculations

Files:

- `lib/sitevoice/projects/calculations/report_count.ex`
- `lib/sitevoice/projects/calculations/last_report_date.ex`

- [x] `ReportCount.calculate/3` — real Ash.count query with `require Ash.Query`
- [x] `LastReportDate.calculate/3` — real query returning last submitted date
- [x] Removed stub comments

## 10. Wire AshJsonApi Router

File: `lib/sitevoice_web/ash_json_api_router.ex`

- [x] Added `Sitevoice.Reporting` to the `domains:` list

## 11. Create UserSocket

File: `lib/sitevoice_web/channels/user_socket.ex`

- [x] `SitevoiceWeb.UserSocket` with JWT verification via `AshAuthentication.Jwt.verify/2`

## 12. Create RecordingChannel

File: `lib/sitevoice_web/channels/recording_channel.ex`

- [x] Full channel with join/authorize, handle_in, Oban job insertion

## 13. Wire UserSocket in Endpoint

File: `lib/sitevoice_web/endpoint.ex`

- [x] Added `socket "/socket", SitevoiceWeb.UserSocket`

## 14. Generate and Apply Migration

- [x] Run `mix ash.codegen recording_resources`
- [x] Verified migration creates `daily_logs` and `photos` tables with indexes
- [x] Applied migration + extra migrations for versions org_id and cascade FK drop

## 15. Tests

All tests tagged `@moduletag slice: :recording`.

- [x] All 19 tests passing across daily_log_test, photo_test, audio_processor_test

## 16. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix test --only slice:recording` — 19 tests, 0 failures
- [x] `mix test` — 53 tests, 0 failures (no regressions)
