# Slice 13 — Lua RBAC

**Goal:** Replace the four hardcoded project-level role atoms with org-owned `OrgRole`
resources whose permission logic is a Lua script evaluated at Ash policy check time.
Enterprise customers can create custom roles (e.g. "Safety Officer") with fine-grained
rules without a redeploy. The four system roles (foreman, pm, owner, org_admin) ship as
seeded defaults so existing behavior is preserved exactly.

## Authorization Architecture After This Slice

### Two-tier model

| Tier | Resource | Check mechanism | Changed? |
|------|----------|-----------------|----------|
| Org-level | User, Organization, Integration | `actor_attribute_equals(:role, :org_admin/owner)` on `User.role` | No |
| Project-level | DailyLog, LogEntry, Photo, DailyAttendance, CrewTemplate, WeeklyReport | `Sitevoice.Policies.LuaPermission` on `ProjectMembership.org_role_id` | Yes |

### Policy pattern after migration (project-level resources)

```elixir
# Org-admin bypass is kept as a hard-coded first clause.
# System pipeline actions (actor_absent) are kept unchanged.
# relates_to_actor_via clauses are kept (they are FilterChecks; Lua cannot replace them).
# actor_attribute_equals(:role, :pm/:foreman/:owner) clauses are replaced by LuaPermission.

policy action([:start_log, :submit_recording, :submit_text_report]) do
  authorize_if actor_attribute_equals(:role, :org_admin)   # kept
  authorize_if Sitevoice.Policies.LuaPermission            # replaces :foreman, :pm
end

policy action(:edit_draft) do
  authorize_if actor_attribute_equals(:role, :org_admin)   # kept
  authorize_if relates_to_actor_via(:foreman)              # kept
  authorize_if Sitevoice.Policies.LuaPermission            # new (for custom PM-like roles)
end

policy action([:read, :list_for_project, ...]) do
  authorize_if actor_attribute_equals(:role, :org_admin)   # kept
  authorize_if relates_to_actor_via(:foreman)              # kept
  authorize_if Sitevoice.Policies.LuaPermission            # replaces :pm, :owner
end
```

### LuaPermission check

`Sitevoice.Policies.LuaPermission` is an `Ash.Policy.SimpleCheck`.

Steps at check time:
1. Extract `project_id` from subject (changeset attribute, record field, or query filter).
   If no project_id can be resolved, fall back to checking all the actor's project roles
   within the org — any matching role grants access.
2. Load `ProjectMembership` for `{actor.id, project_id, actor.organization_id}` —
   use ETS cache keyed by that triple, TTL 60 s.
3. Load `OrgRole` (lua_script) from `RoleCache` keyed by `{org_id, role_id}`.
4. Build Lua `ctx` table (see below).
5. Evaluate `check(ctx)` via `Lua.call_function!/3`.
6. Return `true` if result is `[true]`, otherwise `false`.

### Lua `ctx` table fields

```lua
ctx = {
  action   = "edit_draft",      -- Ash action name as string
  resource = "daily_log",       -- resource short name as string
  actor_id = "uuid-...",        -- actor's user id
  role     = "Safety Officer",  -- OrgRole.name for the actor in this project
}
```

Note: `is_log_foreman` and `is_project_member` relationship flags are intentionally excluded
from ctx for Phase 1. These are handled by the `relates_to_actor_via` clauses that remain
in policies. Phase 2 can add them via `deflua` helpers when section-level checks are needed.

### Default system role Lua scripts

These scripts preserve existing behavior exactly. They are seeded as `is_system_role: true`
and displayed as read-only in the UI.

**foreman:**
```lua
function check(ctx)
  local a = ctx.action
  local r = ctx.resource
  if r == "daily_log" then
    return a == "start_log" or a == "submit_recording" or a == "submit_text_report"
  end
  if r == "log_entry" then
    return a == "add_voice_memo" or a == "add_text_note" or a == "add_photo"
  end
  if r == "photo" then return a == "upload" end
  if r == "daily_attendance" then return a == "create" end
  if r == "crew_template" then return true end
  return false
end
```

**pm:**
```lua
function check(ctx)
  local a = ctx.action
  local r = ctx.resource
  if r == "daily_log" then
    if a == "start_log" or a == "submit_recording" or a == "submit_text_report" then return true end
    if a == "read" or a == "list_for_project" or a == "list_for_date_range"
       or a == "list_for_foreman" or a == "get_today_for_foreman"
       or a == "list_for_date" or a == "list_all" then return true end
    return false
  end
  if r == "log_entry" then
    if a == "add_voice_memo" or a == "add_text_note" or a == "add_photo" then return true end
    if a == "read" or a == "for_log" then return true end
    return false
  end
  if r == "photo" then return a == "upload" or a == "read" end
  if r == "daily_attendance" then
    return a == "create" or a == "update_attendance" or a == "read" or a == "list_for_log"
  end
  if r == "crew_template" then return true end
  if r == "weekly_report" then
    return a == "read" or a == "list_for_project" or a == "get_by_week"
  end
  return false
end
```

**owner:**
```lua
function check(ctx)
  local a = ctx.action
  if a == "read" or a == "get_by_week" or a == "get_today_for_foreman" then return true end
  if string.sub(a, 1, 4) == "list" then return true end
  return false
end
```

**org_admin:** Not a Lua role — continues to be `actor_attribute_equals(:role, :org_admin)`
on `User.role` (org-level bypass, not project-scoped).

## Acceptance Criteria

- [ ] `{:lua, "~> 0.0"}` added to `mix.exs` and compiled
- [ ] `Sitevoice.Accounts.OrgRole` resource exists: tenanted, fields `name`, `description`,
      `lua_script`, `is_system_role`; multitenancy via `organization_id`
- [ ] `Sitevoice.Accounts.Changes.SeedDefaultRoles` runs as `after_action` on
      `Organization :register`; creates foreman, pm, owner system OrgRoles for the new org
- [ ] `ProjectMembership` has `org_role_id` FK to `OrgRole`; old `role` atom made nullable
      (not removed); `:add_member` action accepts `org_role_id`
- [ ] `Sitevoice.RoleCache` GenServer started in application supervision tree; caches
      compiled Lua state per `{org_id, role_id}`; invalidates on OrgRole update
- [ ] `Sitevoice.Policies.LuaPermission` SimpleCheck implemented; passes action + resource
      context to Lua `check(ctx)` function; returns correct boolean
- [ ] DailyLog, LogEntry, Photo, DailyAttendance, CrewTemplate, WeeklyReport policies updated:
      `actor_attribute_equals(:role, :pm/:foreman/:owner)` replaced by `LuaPermission`;
      `org_admin` bypass, `relates_to_actor_via`, `actor_absent` clauses unchanged
- [ ] Existing system roles (seeded) produce identical authorization behavior to the
      previous hardcoded role atoms — verified by running `mix test` with no regressions
- [ ] `/settings/roles` LiveView lists org's OrgRoles; allows create + edit of custom roles;
      system roles shown as read-only
- [ ] ProjectMembership role dropdown in `projects/show_live` shows OrgRole names from the
      org's role list (not hardcoded atoms)
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:lua_rbac` — all tests pass
- [ ] `mix test` — no regressions in slices 00–12

## What This Slice Does NOT Include

- Section/field-level permissions within DailyLog (Phase 2 — requires DailyLog redesign)
- `deflua` Elixir helper functions exposed to Lua (reserved for Phase 2 when ctx needs
  `is_log_foreman`/`is_project_member` flags)
- Removing the old `role` atom from `ProjectMembership` (future cleanup slice)
- Mobile (React Native) changes — Slice 10
- Lua script editor with syntax highlighting (plain textarea is sufficient for MVP)
- Role import/export
- Audit trail for Lua script edits (Ash Paper Trail covers this if enabled on OrgRole)
