# Context — Slice 13: Lua RBAC

## Dependency

Slices 00–12 must be complete. This slice modifies `ProjectMembership`, six reporting resources,
and the LiveView for project membership management.

## Purpose

Replace the four hardcoded role atoms (`:foreman`, `:pm`, `:owner`, `:org_admin`) at the
project level with org-defined `OrgRole` resources whose authorization logic is expressed as
Lua scripts executed at policy-check time via the `lua` hex package (Luerl VM).

This enables enterprise customers to create custom project roles — e.g. "Safety Officer" —
with Lua rules like "can edit entries but read-only on logs" without a redeploy.

Org-level administrative policies (User management, Organization settings, Integration
management) are **not touched** — they stay on `User.role` since they are org-wide concerns,
not project-scoped.

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §4 — User roles and authorization model
2. `docs/CODING_STANDARDS.md` — Ash resource conventions, custom policy checks
3. `CLAUDE.md` — Architecture Rules §Ash, §Multitenancy
4. `lib/sitevoice/projects/project_membership.ex` — current role atom, actions, policies
5. `lib/sitevoice/reporting/daily_log.ex` — all policy blocks (lines 230–274)
6. `lib/sitevoice/reporting/log_entry.ex` — all policy blocks (lines 135–158)
7. `lib/sitevoice/reporting/photo.ex` — all policy blocks (lines 66–87)
8. `lib/sitevoice/reporting/daily_attendance.ex` — all policy blocks (lines 81–104)
9. `lib/sitevoice/reporting/crew_template.ex` — all policy blocks (lines 79–92)
10. `lib/sitevoice/reporting/weekly_report.ex` — all policy blocks (lines 110–121)
11. `lib/sitevoice/accounts/organization.ex` — `:register` action (seeding hook point)
12. `lib/sitevoice_web/live/projects/show_live.ex` — membership role dropdown

## Existing State

- `ProjectMembership.role` — `:atom` field constrained to `[:foreman, :pm, :owner, :org_admin]`
- All project-level Ash policies use `actor_attribute_equals(:role, :X)` — 60+ occurrences
  across DailyLog, LogEntry, Photo, DailyAttendance, CrewTemplate, WeeklyReport
- `relates_to_actor_via(:foreman)` / `relates_to_actor_via([:daily_log, :foreman])` — record-
  level relationship checks in 5 resources; these are **kept as-is** (they are FilterChecks
  that filter read queries — Lua cannot replace them)
- `actor_absent()` checks on system pipeline actions — **kept as-is**
- `actor_attribute_equals(:role, :org_admin)` on org-level resources — **kept as-is**

## New Files To Create

### Ash Resource

- `lib/sitevoice/accounts/org_role.ex` — tenanted `OrgRole` resource; fields: `name` (string),
  `description` (string), `lua_script` (text), `is_system_role` (boolean)

### Ash Change

- `lib/sitevoice/accounts/changes/seed_default_roles.ex` — `after_action` change on
  `Organization :register`; creates the four system OrgRoles for the new org

### Policy Check

- `lib/sitevoice/policies/lua_permission.ex` — `Ash.Policy.SimpleCheck` implementation;
  loads actor's `OrgRole` via `ProjectMembership`, evaluates `check(ctx)` Lua function,
  returns match result

### Role Cache

- `lib/sitevoice/role_cache.ex` — `GenServer` backed by ETS; caches compiled `Lua.State`
  keyed by `{org_id, role_id}`; invalidated on `OrgRole` update

### Lua API Module

- `lib/sitevoice/lua_api.ex` — `use Lua.API, scope: "sv"`; exposes Elixir helpers to Lua
  via `deflua`: `is_project_member/2`, `is_log_foreman/2`

### LiveView

- `lib/sitevoice_web/live/settings/roles_live.ex` — org role management screen;
  list, create, edit OrgRoles with Lua script textarea
- `lib/sitevoice_web/live/settings/roles_live.html.heex`

### Tests

- `test/sitevoice/accounts/org_role_test.exs`
- `test/sitevoice/policies/lua_permission_test.exs`
- `test/sitevoice/role_cache_test.exs`
- `test/sitevoice_web/live/settings/roles_live_test.exs`

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- Add `{:lua, "~> 0.0"}` to `mix.exs` deps (Luerl wrapper)
- `RoleCache` must be added to the application supervision tree in `lib/sitevoice/application.ex`
- All Lua scripts must define a top-level `check(ctx)` function returning a boolean
- `ctx` passed to Lua is a plain table — no Elixir structs; serialize only safe scalar fields
- Lua sandbox: do not enable `[:io]`, `[:os]`, or `[:require]` — default sandbox is correct
- The old `role` atom on `ProjectMembership` is kept (nullable) during this slice for
  backward compat; a future cleanup slice removes it
- `org_role_id` on `ProjectMembership` must be set from actor context or explicit argument —
  never from client request body directly; validate it belongs to the actor's org
- All tests tagged `@moduletag slice: :lua_rbac`
- `mix compile --warnings-as-errors` — zero warnings
