# Tasks — Slice 13: Lua RBAC

Work through in order. Check off each task as it is completed.

---

## 1. Add Lua Dependency

File: `mix.exs`

- [ ] Add `{:lua, "~> 0.0"}` to the `deps` list
- [ ] Run `mix deps.get` to fetch and compile

---

## 2. Create OrgRole Resource

File: `lib/sitevoice/accounts/org_role.ex`

- [ ] Define `Sitevoice.Accounts.OrgRole` with `use Ash.Resource`
- [ ] Multitenancy: `strategy :attribute; attribute :organization_id`
- [ ] Fields:
  - `organization_id` `:uuid`, `allow_nil?: false, public?: false`
  - `name` `:string`, `allow_nil?: false, public?: true`
  - `description` `:string`, `allow_nil?: true, public?: true`
  - `lua_script` `:string`, `allow_nil?: false, public?: true` (stores full Lua source)
  - `is_system_role` `:boolean`, `allow_nil?: false, default: false, public?: true`
  - `timestamps()`
- [ ] Actions:
  - `:read` (primary)
  - `:list_for_org` read action — filter `expr(organization_id == ^actor(:organization_id))`
  - `:create` — `accept [:name, :description, :lua_script]`; `change set_attribute(:organization_id, actor(:organization_id))`; validate `lua_script` compiles (see Task 5)
  - `:update` — `accept [:name, :description, :lua_script]`; same validation; trigger cache invalidation via `after_action` (see Task 5)
  - `:destroy` — forbid if `is_system_role: true` via `validate`
- [ ] Policies:
  - `action_type(:read)`: `authorize_if actor_attribute_equals(:role, :org_admin)` + `authorize_if actor_attribute_equals(:role, :owner)`
  - `action(:create)`: `authorize_if actor_attribute_equals(:role, :org_admin)`
  - `action(:update)`: `authorize_if actor_attribute_equals(:role, :org_admin)` — additionally validate `is_system_role == false` (use `forbid_if` with expression check)
  - `action(:destroy)`: `authorize_if actor_attribute_equals(:role, :org_admin)`
- [ ] Register `OrgRole` in `lib/sitevoice/accounts.ex` domain resources list
- [ ] Generate and run migration: `mix ash.codegen add_org_roles`

---

## 3. Update ProjectMembership

File: `lib/sitevoice/projects/project_membership.ex`

- [ ] Add relationship: `belongs_to :org_role, Sitevoice.Accounts.OrgRole, allow_nil?: true`
- [ ] Make existing `role` atom attribute nullable: `allow_nil?: true` (keep the field; do not remove)
- [ ] Update `:add_member` action: `accept [:user_id, :project_id, :org_role_id]`
- [ ] Add validation on `:add_member`: ensure `org_role_id` belongs to `actor(:organization_id)` — use a custom `Ash.Resource.Validation` that queries `OrgRole` with tenant set
- [ ] Update `:update_role` action: `accept [:org_role_id]` (alongside existing `role`)
- [ ] Generate and run migration: `mix ash.codegen add_org_role_to_memberships`
  - Migration adds `org_role_id uuid references org_roles(id)` (nullable)

---

## 4. Seed Default Roles on Org Registration

File: `lib/sitevoice/accounts/changes/seed_default_roles.ex`

- [ ] Define `Sitevoice.Accounts.Changes.SeedDefaultRoles` — `use Ash.Resource.Change`
- [ ] Implement `change/3` using `Ash.Changeset.after_action/2`
- [ ] In the callback, create four OrgRoles for the new org using `Ash.create!` with
      `authorize?: false` and `tenant: org.id`:
  - `foreman` system role — Lua script from SLICE.md
  - `pm` system role — Lua script from SLICE.md
  - `owner` system role — Lua script from SLICE.md
  - `org_admin` system role — Lua script: `function check(ctx) return true end`
    (org_admin bypass is handled at Ash policy level anyway; this role exists for completeness)
- [ ] Wire change into `Organization :register` action: `change Sitevoice.Accounts.Changes.SeedDefaultRoles`

---

## 5. Create RoleCache GenServer

File: `lib/sitevoice/role_cache.ex`

- [ ] Define `Sitevoice.RoleCache` — `use GenServer`
- [ ] On `start_link`, create ETS table `:role_cache` with `[:set, :public, :named_table]`
- [ ] Implement `get_compiled(org_id, role_id)`:
  - Check ETS for `{org_id, role_id}` — return cached `Lua.State` if found
  - Otherwise load `OrgRole` from DB (`authorize?: false`, `tenant: org_id`)
  - Compile via `Lua.load_chunk!(state, script_source)` on a `Lua.new()` base state
  - Store in ETS and return
- [ ] Implement `invalidate(org_id, role_id)` — delete ETS entry
- [ ] Add `Sitevoice.RoleCache` to the supervision tree in `lib/sitevoice/application.ex`
      (add before `SitevoiceWeb.Endpoint`)
- [ ] Wire invalidation: in `OrgRole :update` action, add `after_action` change that calls
      `Sitevoice.RoleCache.invalidate(org.organization_id, org_role.id)`

---

## 6. Create LuaPermission Policy Check

File: `lib/sitevoice/policies/lua_permission.ex`

- [ ] Define `Sitevoice.Policies.LuaPermission` — `use Ash.Policy.SimpleCheck`
- [ ] Implement `describe(_opts)` — returns `"lua role permission check"`
- [ ] Implement `match?(actor, context, _opts)`:
  1. Extract `org_id` from `actor.organization_id`; return `false` if nil
  2. Extract `project_id` from context subject:
     - If `subject` is an `Ash.Changeset`: try `Ash.Changeset.get_attribute(subject, :project_id)` then `subject.data.project_id`
     - If `subject` is an `Ash.Query`: try `Ash.Query.get_filter_value(subject, :project_id)` (best-effort)
  3. If `project_id` resolved: load the single `ProjectMembership` for `{actor.id, project_id, org_id}` with `authorize?: false`, `tenant: org_id`
  4. If no `project_id`: load ALL `ProjectMembership` records for `{actor.id, org_id}` — return `true` if ANY role matches
  5. Extract `org_role_id` from membership(s); return `false` if nil (membership has no custom role yet)
  6. Load compiled Lua state via `Sitevoice.RoleCache.get_compiled(org_id, org_role_id)`
  7. Build ctx map:
     ```elixir
     %{
       "action"   => to_string(context.action.name),
       "resource" => resource_name(context.resource),
       "actor_id" => actor.id,
       "role"     => membership.org_role.name
     }
     ```
  8. Call `Lua.call_function!(lua_state, ["check"], [ctx])` — returns `[true]` or `[false]`
  9. Rescue `Lua.RuntimeError` / `Lua.CompileError` → log error, return `false`
- [ ] Add private `resource_name/1` helper — maps resource module to short string
      (e.g. `Sitevoice.Reporting.DailyLog` → `"daily_log"`)

---

## 7. Update DailyLog Policies

File: `lib/sitevoice/reporting/daily_log.ex`

Replace `actor_attribute_equals(:role, :foreman/:pm/:owner)` with `LuaPermission`.
Keep `actor_absent()`, `relates_to_actor_via`, and `actor_attribute_equals(:role, :org_admin)` unchanged.

- [ ] `action([:start_log, :submit_recording, :submit_text_report])`:
  Remove `:foreman`, `:pm` clauses → add `authorize_if Sitevoice.Policies.LuaPermission`
- [ ] `action([:submit_entries])`:
  Keep `relates_to_actor_via(:foreman)` and `:org_admin` → add `LuaPermission`
- [ ] `action(:edit_draft)`:
  Keep `relates_to_actor_via(:foreman)` and `:org_admin` → add `LuaPermission`
- [ ] `action(:approve_and_submit)`:
  Keep `relates_to_actor_via(:foreman)` and `:org_admin` → add `LuaPermission`
- [ ] `action([:read, :list_for_project, :list_for_date_range, :list_for_foreman, :get_today_for_foreman, :list_for_date, :list_all])`:
  Keep `relates_to_actor_via(:foreman)` and `:org_admin` → remove `:pm`, `:owner` → add `LuaPermission`
- [ ] `action(:destroy)`:
  Keep `forbid_if expr(status == :submitted)`, `relates_to_actor_via(:foreman)`, `:org_admin` → add `LuaPermission`
- [ ] `action([:apply_transcript, :apply_structure, :mark_failed, :undo_*, :update_pdf])`:
  No change — these are system/pipeline actions

---

## 8. Update LogEntry Policies

File: `lib/sitevoice/reporting/log_entry.ex`

- [ ] `action([:add_voice_memo, :add_text_note, :add_photo])`:
  Remove `:foreman`, `:pm` → add `LuaPermission`
- [ ] `action(:remove_entry)`:
  Keep `relates_to_actor_via([:daily_log, :foreman])` and `:org_admin` → add `LuaPermission`
- [ ] `action([:read, :for_log])`:
  Keep `relates_to_actor_via([:daily_log, :foreman])` and `:org_admin` → remove `:pm`, `:owner` → add `LuaPermission`
- [ ] `action([:apply_transcript, :mark_transcription_failed, :apply_caption])`:
  No change — system/pipeline actions

---

## 9. Update Photo Policies

File: `lib/sitevoice/reporting/photo.ex`

- [ ] `action(:upload)`: Remove `:foreman`, `:pm` → add `LuaPermission`
- [ ] `action(:read)`: Keep `relates_to_actor_via` and `:org_admin` → remove `:pm` → add `LuaPermission`
- [ ] `action(:destroy)`: Keep `relates_to_actor_via` and `:org_admin` → add `LuaPermission`
- [ ] `action(:apply_caption)`: No change

---

## 10. Update DailyAttendance Policies

File: `lib/sitevoice/reporting/daily_attendance.ex`

- [ ] `action([:create])`: Remove `:foreman`, `:pm` → add `LuaPermission`
- [ ] `action([:update_attendance])`: Keep `relates_to_actor_via` and `:org_admin` → remove `:pm` → add `LuaPermission`
- [ ] `action([:read, :list_for_log])`: Keep `relates_to_actor_via` and `:org_admin` → remove `:pm`, `:owner` → add `LuaPermission`
- [ ] `action([:create_from_system])`: No change

---

## 11. Update CrewTemplate Policies

File: `lib/sitevoice/reporting/crew_template.ex`

- [ ] `action([:create, :update, :destroy])`: Remove `:foreman`, `:pm` → add `LuaPermission`
- [ ] `action([:read, :list_for_project, :list_all_for_project])`: Remove `:foreman`, `:pm`, `:owner` → add `LuaPermission`
- [ ] Keep `:org_admin` clauses on all actions

---

## 12. Update WeeklyReport Policies

File: `lib/sitevoice/reporting/weekly_report.ex`

- [ ] `action([:read, :list_for_project, :get_by_week])`: Remove `:pm`, `:owner` → add `LuaPermission`
- [ ] Keep `:org_admin` clause; keep system action policies unchanged

---

## 13. Update ProjectMembership Policies

File: `lib/sitevoice/projects/project_membership.ex`

The ProjectMembership policies check the ACTOR's User.role (org-level) — not a project role.
These stay as `actor_attribute_equals(:role, :X)` since ProjectMembership management is an
org-admin concern. No changes needed here.

- [ ] Confirm policies are unchanged (no LuaPermission added to this resource)

---

## 14. LiveView — Roles Management Screen

File: `lib/sitevoice_web/live/settings/roles_live.ex`
File: `lib/sitevoice_web/live/settings/roles_live.html.heex`

- [ ] `mount/3`: redirect unless `current_user.role in [:org_admin, :owner]`
- [ ] Load all OrgRoles for the org via `Sitevoice.Accounts.list_org_roles/1`
- [ ] `handle_event("new_role")`: open modal/inline form with blank name + description + lua_script
- [ ] `handle_event("edit_role", %{"id" => id})`: open form pre-filled for existing custom role
- [ ] `handle_event("save_role", params)`: call `Ash.create!` or `Ash.update!`; flash on success/error
- [ ] `handle_event("delete_role", %{"id" => id})`: call `Ash.destroy!`; system roles show no delete button
- [ ] Template: table of roles (name, description, system badge, edit/delete actions);
      form with `<textarea>` for lua_script; system roles rendered with `disabled` textarea
- [ ] Add route in `lib/sitevoice_web/router.ex` under settings scope:
      `live "/settings/roles", RolesLive, :index`
- [ ] Add "Roles" nav link in `nav_component.ex` settings section (visible to org_admin/owner)
- [ ] Add domain function `Sitevoice.Accounts.list_org_roles/1` in `lib/sitevoice/accounts.ex`

---

## 15. Update Project Membership LiveView

File: `lib/sitevoice_web/live/projects/show_live.ex`

- [ ] Replace hardcoded role atom options in the membership role dropdown with org's OrgRoles
      loaded via `Sitevoice.Accounts.list_org_roles(tenant: current_user.organization_id)`
- [ ] Dropdown option: `{role.name, role.id}` — value is `org_role_id` UUID
- [ ] `handle_event("add_member")`: pass `org_role_id` (UUID) instead of `role` atom
- [ ] `handle_event("update_member_role")`: pass `org_role_id` (UUID) to `:update_role` action
- [ ] Update display of existing member roles: show `membership.org_role.name` (load association)
      with fallback to `membership.role` atom for memberships not yet migrated

---

## 16. Write Tests

### OrgRole resource test

File: `test/sitevoice/accounts/org_role_test.exs`

- [ ] `@moduletag slice: :lua_rbac`
- [ ] Test create with valid Lua script succeeds
- [ ] Test create with Lua script that has syntax error returns changeset error
- [ ] Test update of system role is forbidden
- [ ] Test destroy of system role is forbidden
- [ ] Test organization_id cannot be set via action params (set from actor JWT)

### LuaPermission check test

File: `test/sitevoice/policies/lua_permission_test.exs`

- [ ] `@moduletag slice: :lua_rbac`
- [ ] Test: actor with `pm` system role can read daily_log (`check(ctx)` returns true)
- [ ] Test: actor with `foreman` system role cannot read daily_log for another foreman's project
- [ ] Test: actor with custom role whose script returns `false` is denied
- [ ] Test: Lua runtime error in script is rescued and returns false (not a crash)
- [ ] Test: actor with no ProjectMembership (org_role_id nil) is denied

### RoleCache test

File: `test/sitevoice/role_cache_test.exs`

- [ ] `@moduletag slice: :lua_rbac`
- [ ] Test cache miss loads from DB and stores compiled state
- [ ] Test cache hit returns same state without DB call
- [ ] Test invalidation clears entry (next get triggers DB load)

### Roles LiveView test

File: `test/sitevoice_web/live/settings/roles_live_test.exs`

- [ ] `@moduletag slice: :lua_rbac`
- [ ] Non-admin user is redirected from `/settings/roles`
- [ ] Org admin sees list of seeded system roles
- [ ] Org admin can create a custom role with valid Lua script
- [ ] Creating a role with invalid Lua shows inline error
- [ ] System roles have no edit/delete controls

---

## 17. Verify

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:lua_rbac` — all tests pass
- [ ] `mix test` — no regressions in slices 00–12
- [ ] Manual smoke test: log in as a PM user, confirm daily log list loads; log in as a
      foreman, confirm they can submit a log; create a custom "Read Only" role (script: all
      read actions return true, write actions return false), assign to a user, confirm they
      cannot submit a log but can view it
