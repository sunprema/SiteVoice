# Context — Slice 01: Auth

## Dependency

Slice 00 (Foundation) must be complete before starting this slice.

## What To Read First

Load these files before touching any code:

1. `docs/DOMAIN_MODEL.md` §3 — SiteVoice.Accounts (Organization, User, Token)
2. `docs/DOMAIN_MODEL.md` §8 — Changes Reference (`HashPassword`)
3. `docs/DOMAIN_MODEL.md` §11 — Policy Matrix (auth-related rows)
4. `docs/CODING_STANDARDS.md` — conventions for Changes, multitenancy, Policies
5. `CLAUDE.md` — Architecture Rules §Ash, §Multitenancy

## Existing Files To Load

These files already exist and will be modified:

- `lib/sitevoice/accounts/user.ex` — AshAuthentication igniter scaffold; extend, do not replace
- `lib/sitevoice/accounts.ex` — domain module; add new resources
- `lib/sitevoice/accounts/organization.ex` — tenant root created in Slice 00
- `lib/sitevoice/secrets.ex` — signing secret callback; verify `extra_token_fields` support
- `lib/sitevoice_web/router.ex` — add `SetTenant` and `VerifyToken` plugs to `:api` pipeline
- `config/config.exs` — verify `ash_domains` list
- `test/support/conn_case.ex` — may need tenant helpers
- `test/support/data_case.ex` — may need tenant helpers

## New Files To Create

- `lib/sitevoice/accounts/changes/hash_password.ex`
- `lib/sitevoice/accounts/actions/register_organization.ex` — org + first user in one transaction
- `lib/sitevoice_web/plugs/set_tenant.ex`
- `lib/sitevoice_web/plugs/verify_token.ex`
- `test/sitevoice/accounts/user_test.exs`
- `test/sitevoice/accounts/register_organization_test.exs`
- `test/sitevoice_web/plugs/set_tenant_test.exs`

## Key Constraints

- `organization_id` is NEVER accepted from client request bodies — JWT only in all post-slice-01 actions
- The `invite` action sets `organization_id` from `actor(:organization_id)`, never from params
- Email uniqueness is per-org (`[:organization_id, :email]`), not global
- The existing AshAuthentication-generated actions (`register_with_password`, `sign_in_with_password`, etc.) must remain intact — only extend, do not replace
- `extra_token_fields: [:organization_id]` must be verified to appear in JWT `claims`
- All tests tagged `@moduletag slice: :auth`
