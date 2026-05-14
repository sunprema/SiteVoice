# Slice 02 — Projects

**Goal:** Tenanted `Project` and `ProjectMembership` resources with AshJsonApi endpoints,
Ash Policies enforcing role-based access, and the NormalizeCode change that keeps project
codes uppercase.

## Acceptance Criteria

- [ ] `SiteVoice.Projects` domain module exists and lists both resources
- [ ] `SiteVoice.Projects.Project` is tenanted — has `multitenancy` block, `organization_id`
      attribute, all attributes from the domain model (`name`, `code`, `address`, `timezone`, `active`)
- [ ] `Project` `:code` identity is unique per org (`[:organization_id, :code]`)
- [ ] `Project` `:create` action sets `organization_id` from `actor(:organization_id)`, never from params
- [ ] `Project` `:archive` action soft-deletes by setting `active: false` (does not destroy the row)
- [ ] `Projects.Changes.NormalizeCode` upcases and trims `:code` on `:create`
- [ ] `Projects.Calculations.ReportCount` and `Projects.Calculations.LastReportDate` are defined
      (may return stub values until Slice 03 adds DailyLog)
- [ ] `SiteVoice.Projects.ProjectMembership` is tenanted — has `multitenancy` block,
      `organization_id`, `role`, and belongs_to relationships for organization, user, and project
- [ ] `ProjectMembership` identity unique on `[:organization_id, :project_id, :user_id]`
- [ ] `ProjectMembership` `:add_member` sets `organization_id` from actor, never from params
- [ ] All Ash Policies match the policy matrix:
  - Project `:create` → org_admin, pm
  - Project `:read` → org_admin, pm, owner; foreman only if a member of the project
  - Project `:update` → org_admin, pm
  - Project `:archive` → org_admin only
  - ProjectMembership `:add_member` → org_admin, pm
  - ProjectMembership `:read` → org_admin, pm
  - ProjectMembership `:update_role` → org_admin only
  - ProjectMembership `:remove_member` → org_admin only
- [ ] `Organization` gains `has_many :projects, SiteVoice.Projects.Project`
- [ ] `User` gains `has_many :project_memberships, SiteVoice.Projects.ProjectMembership`
- [ ] AshJsonApi routes wired for Projects (`GET/POST /projects`, `GET/PATCH/DELETE /projects/:id`)
- [ ] AshJsonApi routes wired for ProjectMemberships (`GET/POST /projects/:id/memberships`, `PATCH /memberships/:id`)
- [ ] `SiteVoice.Projects` added to `ash_domains` in config and to `AshJsonApiRouter` domains list
- [ ] `mix ash.codegen projects_resources` generates migration with `projects` and `project_memberships` tables
- [ ] `mix ash.setup` runs clean after migration
- [ ] All projects tests pass (`mix test --only slice:projects`)
- [ ] `mix test` — no regressions in other tests

## What This Slice Does NOT Include

- No DailyLog resource (Slice 03)
- No Oban workers or async jobs
- No mobile client
- No Tigris storage keys (those are keyed by `project_id` but managed in later slices)

## Key Behaviors

### NormalizeCode
`Projects.Changes.NormalizeCode` must run in the `:create` action before save.
It reads `:code` from the changeset, strips whitespace, upcases, and writes it back.
The result: `"  meridian-001 "` → `"MERIDIAN-001"`.

### Foreman Membership Policy
Foremen are not visible to all projects in their org — only projects they have a
`ProjectMembership` row for. The policy uses:
```elixir
authorize_if relates_to_actor_via([:memberships, :user])
```

### Soft-Delete Archive
`Project.:archive` is declared as a `destroy` action but does NOT delete the row.
Instead it changes `active` to `false` via `change set_attribute(:active, false)`.
This preserves historical daily logs attached to the project.

### AshJsonApi Router
`SiteVoice.Projects` must be added to the `domains:` list in
`SitevoiceWeb.AshJsonApiRouter`. Without this, all JSON:API project routes return 404.
