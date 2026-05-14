# Context — Slice 03: Recording

## Dependency

Slice 02 (Projects) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/DOMAIN_MODEL.md` §5 — SiteVoice.Reporting (DailyLog, Photo)
2. `docs/DOMAIN_MODEL.md` §8 — Changes Reference (`EnqueueProcessing`, `DispatchIntegrations`)
3. `docs/DOMAIN_MODEL.md` §9 — Calculations Reference (`PdfUrl`, `AudioUrl`, `IsLate`, `PhotoUrl`)
4. `docs/DOMAIN_MODEL.md` §10 — JSONB Field Schemas (labor, progress, equipment, materials, delays, safety)
5. `docs/DOMAIN_MODEL.md` §11 — Policy Matrix (DailyLog and Photo rows)
6. `docs/DOMAIN_MODEL.md` §12 — AshJsonApi Route Map (DailyLogs and Photos)
7. `docs/APPLICATION_SPEC.md` §12 — File Storage (Tigris config, org-prefixed key structure, Storage module)
8. `docs/APPLICATION_SPEC.md` §11.1 — Phoenix Channel — Recording (RecordingChannel scaffold)
9. `docs/APPLICATION_SPEC.md` §6.7 — Phoenix Channels — Tenant Propagation
10. `CLAUDE.md` — Architecture Rules §Ash, §Multitenancy, §Oban

## Existing Files To Load

These files already exist and will be modified:

- `lib/sitevoice/projects/calculations/report_count.ex` — implement real count using DailyLog
- `lib/sitevoice/projects/calculations/last_report_date.ex` — implement real date using DailyLog
- `lib/sitevoice/projects/project.ex` — add `has_many :daily_logs` relationship
- `lib/sitevoice/accounts/user.ex` — relationship already declared (forward ref, verify it compiles)
- `lib/sitevoice_web/ash_json_api_router.ex` — add `SiteVoice.Reporting` to domains list
- `config/config.exs` — add `SiteVoice.Reporting` to `ash_domains`
- `lib/sitevoice_web/endpoint.ex` — wire UserSocket if not already done
- `lib/sitevoice/storage.ex` — already exists; verify it has all key helper functions
- `test/support/conn_case.ex` — verify tenant helpers present (from Slice 01)
- `test/support/data_case.ex` — verify tenant helpers present (from Slice 01)

## New Files To Create

- `lib/sitevoice/reporting.ex` — domain module
- `lib/sitevoice/reporting/daily_log.ex`
- `lib/sitevoice/reporting/photo.ex`
- `lib/sitevoice/reporting/changes/enqueue_processing.ex`
- `lib/sitevoice/reporting/changes/dispatch_integrations.ex`
- `lib/sitevoice/reporting/calculations/pdf_url.ex`
- `lib/sitevoice/reporting/calculations/audio_url.ex`
- `lib/sitevoice/reporting/calculations/is_late.ex`
- `lib/sitevoice/reporting/calculations/photo_url.ex`
- `lib/sitevoice/workers/audio_processor.ex`
- `lib/sitevoice_web/channels/user_socket.ex`
- `lib/sitevoice_web/channels/recording_channel.ex`
- `test/sitevoice/reporting/daily_log_test.exs`
- `test/sitevoice/reporting/photo_test.exs`
- `test/sitevoice/workers/audio_processor_test.exs`

## Key Constraints

- `organization_id` is NEVER accepted from client request bodies — set via `actor(:organization_id)` in `:submit_recording` and `Photo.:upload`
- `foreman_id` is set from `actor(:id)` in `:submit_recording`, never from params
- `EnqueueProcessing` must use `Ash.Changeset.after_action/2` so the Oban job is only inserted after the DailyLog row is committed; job args MUST include `organization_id`
- `DispatchIntegrations` is wired to `:approve_and_submit` but that action is deferred to Slice 04 AI pipeline. Define the Change module now but it can be a stub that returns `{:ok, log}` with a TODO comment
- `AudioProcessor` worker's `perform/1` must call `Ash.set_tenant(org_id)` as its very first line before any Ash operations
- All Tigris storage keys must be org-prefixed: `{organization_id}/{project_id}/{date}/{log_id}.m4a`
- `RecordingChannel`: set tenant on `join` and re-apply on every `handle_in`
- `RecordingChannel`: authorize that the joining user owns the log (prevent cross-user channel access)
- The `DispatchIntegrations` Change module can return `{:ok, log}` as a stub (Slice 08 implements the actual dispatch)
- Stub calculations `ReportCount` and `LastReportDate` in Slice 02 should now be implemented using real DailyLog queries
- All tests tagged `@moduletag slice: :recording`
