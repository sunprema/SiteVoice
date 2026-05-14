# Context — Slice 02: Projects

## Dependency

Slice 01 (Auth) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/DOMAIN_MODEL.md` §4 — SiteVoice.Projects (Project, ProjectMembership)
2. `docs/DOMAIN_MODEL.md` §8 — Changes Reference (`NormalizeCode`)
3. `docs/DOMAIN_MODEL.md` §11 — Policy Matrix (Project and ProjectMembership rows)
4. `docs/DOMAIN_MODEL.md` §12 — AshJsonApi Route Map (Projects and Project Memberships)
5. `docs/CODING_STANDARDS.md` — conventions for Changes, Calculations, multitenancy, Policies
6. `CLAUDE.md` — Architecture Rules §Ash, §Multitenancy

## Existing Files To Load

These files already exist and will be modified:

- `lib/sitevoice/accounts/organization.ex` — add `has_many :projects` relationship
- `lib/sitevoice/accounts/user.ex` — add `has_many :project_memberships` relationship
- `lib/sitevoice_web/ash_json_api_router.ex` — add `SiteVoice.Projects` to domains list
- `config/config.exs` — add `SiteVoice.Projects` to `ash_domains`
- `test/support/conn_case.ex` — verify tenant helpers are present (from Slice 01)
- `test/support/data_case.ex` — verify tenant helpers are present (from Slice 01)

## New Files To Create

- `lib/sitevoice/projects.ex` — domain module
- `lib/sitevoice/projects/project.ex`
- `lib/sitevoice/projects/project_membership.ex`
- `lib/sitevoice/projects/changes/normalize_code.ex`
- `lib/sitevoice/projects/calculations/report_count.ex`
- `lib/sitevoice/projects/calculations/last_report_date.ex`
- `test/sitevoice/projects/project_test.exs`
- `test/sitevoice/projects/project_membership_test.exs`

## Key Constraints

- `organization_id` is NEVER accepted from client request bodies — set via `actor(:organization_id)` in the `:create` and `:add_member` actions
- Foremen can only read projects they are explicitly a member of (`relates_to_actor_via([:memberships, :user])`)
- `NormalizeCode` must upcase and trim the `:code` attribute — project codes are always uppercase (e.g. `"meridian-001"` → `"MERIDIAN-001"`)
- `ReportCount` and `LastReportDate` calculations reference `SiteVoice.Reporting.DailyLog` which does not exist yet — stub these as returning `nil`/`0` with a `TODO: Slice 03` note, OR define them as Ash calculations that can be loaded lazily once the DailyLog resource exists
- The `:archive` destroy action is a soft-delete — it sets `active: false`, does not delete the row
- All tests tagged `@moduletag slice: :projects`
