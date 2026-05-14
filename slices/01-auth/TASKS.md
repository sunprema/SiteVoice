# Tasks — Slice 01: Auth

Work through in order. Check off each task as it is completed.

---

## 1. Update User Resource

- [x] Add `multitenancy do strategy :attribute; attribute :organization_id end` block
- [x] Add attributes: `organization_id` (uuid, not null, public?: false),
      `name` (string, not null), `role` (atom, one_of: [:foreman, :pm, :owner, :org_admin],
      default: :foreman), `preferred_language` (atom, one_of: [:en, :es], default: :en)
- [x] Remove existing global `:unique_email` identity; add `:unique_email_per_org`
      identity on `[:organization_id, :email]`
- [x] Add `postgres custom_indexes`: `[:organization_id]`, `[:organization_id, :email]`
      (unique: true), `[:organization_id, :role]`
- [x] Add `extra_token_fields: [:organization_id]` to `tokens` block
      (N/A — AshAuthentication 4.13.7 automatically includes tenant claim; use global? true + SetTenantMetadata preparation instead)
- [x] Add `invite` action: accepts `[:email, :name, :role, :preferred_language]`,
      sets `organization_id` from `actor(:organization_id)`, calls `Changes.HashPassword`
- [x] Rename/remove the old `register_with_password` email field type — change
      `:email` attribute from `:ci_string` to `:string` if needed for multitenancy
      compatibility (keep AshAuthentication's `identity_field :email` intact)
- [x] Add `update_profile` action (accept: `[:name, :preferred_language]`)
- [x] Add `update_role` action (accept: `[:role]`)
- [x] Update policies per domain model policy matrix (invite, read, update_profile,
      update_role, destroy)
- [x] Add `paper_trail do attributes_as_attributes [:organization_id] end`
- [x] Add `belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false`
      relationship

## 2. Update Organization Resource

- [x] Add `has_many :users, Sitevoice.Accounts.User` relationship
      (now valid since User will have `organization_id`)

## 3. Create Changes.HashPassword

File: `lib/sitevoice/accounts/changes/hash_password.ex`

- [x] Implement `Ash.Resource.Change` behaviour
- [x] Hash the `:password` argument using `Bcrypt.hash_pwd_salt/1` and store in
      `:hashed_password` attribute

## 4. Generate Migration

- [x] Run `mix ash.codegen auth_user_tenancy`
- [x] Verify migration adds: `organization_id`, `name`, `role`, `preferred_language`
      columns, drops old `unique_email` index, adds new `unique_email_per_org` index
- [x] Run `mix ash.migrate` to apply

## 5. Create RegisterOrganization Action

File: `lib/sitevoice/accounts/actions/register_organization.ex`

- [x] Define a plain module (not an Ash resource action) with `call/1`
- [x] Accept `%{org_name: _, user_email: _, user_password: _, user_name: _}`
- [x] Wrap in `Ash.transact/2` with both resources:
  1. `Sitevoice.Accounts.Organization |> Ash.Changeset.for_create(:register, %{name: org_name}) |> Ash.create!()`
  2. Build user with `organization_id: org.id`, `role: :org_admin`, call `register_with_password`
- [x] Return `{:ok, %{organization: org, user: user, token: token}}`
- [x] Return `{:error, reason}` on failure (rollback handled by transaction)

## 6. Create SetTenant Plug

File: `lib/sitevoice_web/plugs/set_tenant.ex`

- [x] Implement `Plug.init/1` and `Plug.call/2`
- [x] Read `organization_id` from `conn.assigns[:current_user]`
- [x] Call `Ash.PlugHelpers.set_tenant(conn, organization_id)` when actor is present
- [x] No-op (pass through) when `current_user` is nil

## 7. Create VerifyToken Plug

File: `lib/sitevoice_web/plugs/verify_token.ex`

- [x] Implement `Plug.init/1` and `Plug.call/2`
- [x] If `conn.assigns[:current_user]` is nil, halt with `401` JSON error
- [x] Otherwise pass through

## 8. Wire Plugs into Router

File: `lib/sitevoice_web/router.ex`

- [x] In the `:api` pipeline, add `plug SitevoiceWeb.Plugs.SetTenant` after
      `plug :set_actor, :user`

## 9. Tests

All tests tagged `@moduletag slice: :auth`.

- [x] `test/sitevoice/accounts/user_test.exs`
  - [x] `invite` creates user in same org as actor
  - [x] `invite` is rejected for non-org_admin actor
  - [x] `update_profile` is rejected when actor ≠ user
  - [x] `update_role` is rejected for non-org_admin
  - [x] `destroy` is rejected if actor tries to destroy themselves
  - [x] JWT token from `sign_in_with_password` contains `organization_id` claim

- [x] `test/sitevoice/accounts/register_organization_test.exs`
  - [x] Creates org and first user in one call
  - [x] Returns token
  - [x] Rolls back org creation if user creation fails

- [x] `test/sitevoice_web/plugs/set_tenant_test.exs`
  - [x] Sets Ash tenant when actor present
  - [x] No-op when actor absent

## 10. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [x] `mix ash.setup` — runs clean
- [x] `mix test --only slice:auth` — all passing
- [x] `mix test` — no regressions in other tests
