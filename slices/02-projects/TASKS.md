# Tasks — Slice 02: Projects

Work through in order. Check off each task as it is completed.

---

## 1. Create the Projects Domain Module

File: `lib/sitevoice/projects.ex`

- [x] Define `SiteVoice.Projects` with `use Ash.Domain`
- [x] List both resources: `SiteVoice.Projects.Project` and `SiteVoice.Projects.ProjectMembership`
- [x] Add domain to `ash_domains` in `config/config.exs`

## 2. Create NormalizeCode Change

File: `lib/sitevoice/projects/changes/normalize_code.ex`

- [x] Implement `Ash.Resource.Change` behaviour
- [x] In `change/3`, read `:code` from changeset, apply `String.trim/1` then `String.upcase/1`,
      write back with `Ash.Changeset.change_attribute/3`

## 3. Create Stub Calculations

Files:
- `lib/sitevoice/projects/calculations/report_count.ex`
- `lib/sitevoice/projects/calculations/last_report_date.ex`

- [x] Implement `Ash.Resource.Calculation` behaviour for each
- [x] `ReportCount.calculate/3` returns `{:ok, Enum.map(records, fn _ -> 0 end)}`
- [x] `LastReportDate.calculate/3` returns `{:ok, Enum.map(records, fn _ -> nil end)}`
- [x] Add a single-line comment on each: `# Implemented in Slice 03 when DailyLog exists`

## 4. Create Project Resource

File: `lib/sitevoice/projects/project.ex`

- [x] `use Ash.Resource` with `domain: SiteVoice.Projects`, `data_layer: AshPostgres.DataLayer`,
      `extensions: [AshJsonApi.Resource, AshPaperTrail.Resource]`
- [x] Add `multitenancy do strategy :attribute; attribute :organization_id end` block
- [x] Add `postgres` block: table `"projects"`, repo `SiteVoice.Repo`, custom_indexes:
      `[:organization_id]`, `[:organization_id, :code]` (unique: true), `[:organization_id, :active]`
- [x] Add all attributes: `uuid_primary_key :id`, `organization_id` (uuid, not null, public?: false),
      `name` (string, not null), `code` (string, not null), `address` (string), `timezone` (string,
      default: `"America/Phoenix"`), `active` (boolean, default: true, not null), `timestamps()`
- [x] Add identity: `:unique_code_per_org` on `[:organization_id, :code]`
- [x] Add relationships: `belongs_to :organization`, `has_many :memberships, SiteVoice.Projects.ProjectMembership`
      (daily_logs and integrations are forward-refs, deferred to Slice 03/08)
- [x] Add calculations: `report_count` and `last_report_date` referencing their modules
- [x] Add actions per domain model:
  - `:create` — accept `[:name, :code, :address, :timezone]`,
    `change set_attribute(:organization_id, actor(:organization_id))`,
    `change SiteVoice.Projects.Changes.NormalizeCode`
  - `:read` (primary? true) — `prepare build(load: [:report_count, :last_report_date])`
  - `:list_active` read — `filter expr(active == true)`
  - `:update` — accept `[:name, :address, :timezone, :active]`
  - `:archive` destroy — `soft? true`, `change set_attribute(:active, false)`
- [x] Add policies per policy matrix (create, read, update, archive)
- [x] Add `paper_trail do store_action_name? true; attributes_as_attributes [:organization_id] end`
- [x] Add `json_api do` block: type `"project"`, routes base `"/projects"`,
      `index :read`, `get :read`, `post :create`, `patch :update`, `delete :archive`

## 5. Create ProjectMembership Resource

File: `lib/sitevoice/projects/project_membership.ex`

- [x] `use Ash.Resource` with `domain: SiteVoice.Projects`, `data_layer: AshPostgres.DataLayer`
      (no AshJsonApi extension — routes handled via Project's nested routes or separate base)
- [x] Add `multitenancy do strategy :attribute; attribute :organization_id end` block
- [x] Add `postgres` block: table `"project_memberships"`, repo `SiteVoice.Repo`, custom_indexes:
      `[:organization_id, :project_id, :user_id]` (unique: true),
      `[:organization_id, :user_id]`,
      `[:organization_id, :project_id]`
- [x] Add attributes: `uuid_primary_key :id`, `organization_id` (uuid, not null, public?: false),
      `role` (atom, constraints: `[one_of: [:foreman, :pm, :owner, :org_admin]]`, not null),
      `timestamps()`
- [x] Add identity: `:unique_membership` on `[:organization_id, :project_id, :user_id]`
- [x] Add relationships: `belongs_to :organization`, `belongs_to :user, SiteVoice.Accounts.User`,
      `belongs_to :project, SiteVoice.Projects.Project`
- [x] Add actions per domain model:
  - `:add_member` create — accept `[:user_id, :project_id, :role]`,
    `change set_attribute(:organization_id, actor(:organization_id))`
  - `:read` (primary? true)
  - `:update_role` update — accept `[:role]`
  - `:remove_member` destroy
- [x] Add policies per policy matrix (add_member, read, update_role, remove_member)

## 6. Update Organization Resource

File: `lib/sitevoice/accounts/organization.ex`

- [x] Add `has_many :projects, SiteVoice.Projects.Project`

## 7. Update User Resource

File: `lib/sitevoice/accounts/user.ex`

- [x] Add `has_many :project_memberships, SiteVoice.Projects.ProjectMembership`

## 8. Wire AshJsonApi Router

File: `lib/sitevoice_web/ash_json_api_router.ex`

- [x] Add `SiteVoice.Projects` to the `domains:` list

## 9. Generate and Apply Migration

- [x] Run `mix ash.codegen projects_resources`
- [x] Verify migration creates `projects` table with all columns and indexes
- [x] Verify migration creates `project_memberships` table with all columns and indexes
- [x] Run `mix ash.migrate` to apply

## 10. Tests

All tests tagged `@moduletag slice: :projects`.

- [x] `test/sitevoice/projects/project_test.exs`
  - [x] `:create` sets `organization_id` from actor, not params
  - [x] `:create` runs NormalizeCode — code is stored uppercase
  - [x] `:create` is rejected for a foreman actor
  - [x] `:read` (primary) returns projects for org_admin
  - [x] `:read` returns only member projects for a foreman actor
  - [x] `:read` is rejected for a foreman not in the project
  - [x] `:update` succeeds for pm actor
  - [x] `:archive` succeeds for org_admin — sets `active: false`, does not delete row
  - [x] `:archive` is rejected for pm actor

- [x] `test/sitevoice/projects/project_membership_test.exs`
  - [x] `:add_member` creates membership with `organization_id` from actor
  - [x] `:add_member` is rejected for a foreman actor
  - [x] `:update_role` is rejected for a pm actor
  - [x] `:remove_member` is rejected for a pm actor
  - [x] Duplicate membership (same org/project/user) is rejected by identity constraint

## 11. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix ash.setup` — runs clean
- [x] `mix test --only slice:projects` — all passing
- [x] `mix test` — no regressions in other tests
