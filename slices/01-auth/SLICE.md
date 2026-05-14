# Slice 01 — Auth

**Goal:** Tenanted User resource, JWT with `organization_id` claim, registration flow
(org + first user), and the two plugs that establish tenant context on every API request.

## Acceptance Criteria

- [ ] `Sitevoice.Accounts.User` is tenanted — has `organization_id`, `multitenancy` block,
      `name`, `role`, `preferred_language` attributes
- [ ] Email identity is per-org (`[:organization_id, :email]`), not global
- [ ] JWT issued on sign-in includes `organization_id` in claims
- [ ] `register_with_password` action still works (AshAuthentication flow preserved)
- [ ] `invite` action creates a user inside the caller's org (org_admin only)
- [ ] `update_profile` and `update_role` actions exist with correct policies
- [ ] `Sitevoice.Accounts.Organization` gains `has_many :users` relationship
- [ ] `RegisterOrganization` action creates org + first user atomically in one transaction
- [ ] `SitevoiceWeb.Plugs.SetTenant` reads `organization_id` from JWT claims and calls `Ash.set_tenant/1`
- [ ] `SitevoiceWeb.Plugs.VerifyToken` rejects requests without a valid Bearer token on protected routes
- [ ] `:api` pipeline in router uses `SetTenant` plug after `load_from_bearer`
- [ ] `mix ash.setup` runs clean after migration
- [ ] All auth tests pass (`mix test --only slice:auth`)

## What This Slice Does NOT Include

- No project-scoped resources (Slice 02)
- No Oban workers or async jobs
- No AshJsonApi routes (those are wired per-domain in later slices)
- No mobile client — only the server-side auth layer

## Key Behaviors

### JWT Claim
After sign-in, the token payload must include:
```json
{ "organization_id": "<uuid>", "sub": "user:<uuid>", ... }
```
`Sitevoice.Secrets` already implements `secret_for/4`; extend it if needed for
`extra_token_fields`.

### SetTenant Plug
```
conn → load_from_bearer → set_actor(:user) → SetTenant
```
`SetTenant` reads `conn.assigns.current_user.organization_id` and calls
`Ash.set_tenant(organization_id)`. If the actor is nil (unauthenticated), it is a no-op
— route-level authentication is the VerifyToken plug's job.

### VerifyToken Plug
Rejects with `401` if no valid Bearer token is present. Used on routes that require
authentication. Does NOT replace `load_from_bearer` — it runs after it.

### RegisterOrganization
Single entry point for onboarding. Accepts `org_name`, `user_email`, `user_password`,
`user_name`. Wraps two Ash actions in `Ash.transaction/2`:
1. `Organization.register/1` — creates org, generates slug
2. `User.register_with_password/1` — creates first user with `role: :org_admin`,
   `organization_id` set to new org's id

Returns `{:ok, %{organization: org, user: user, token: jwt}}` on success.
