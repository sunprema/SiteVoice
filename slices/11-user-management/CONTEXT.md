# Slice 11 — User Management — Context

## Spec Sections
- Accounts domain: `lib/sitevoice/accounts/user.ex`, `lib/sitevoice/accounts/organization.ex`
- Projects domain: `lib/sitevoice/projects/project_membership.ex`
- Web: `lib/sitevoice_web/router.ex`, `lib/sitevoice_web/components/nav_component.ex`
- Existing LiveViews: `lib/sitevoice_web/live/projects/show_live.ex`

## Key Files to Load
- `lib/sitevoice/accounts/user.ex`
- `lib/sitevoice/accounts/organization.ex`
- `lib/sitevoice/projects/project_membership.ex`
- `lib/sitevoice/accounts.ex`
- `lib/sitevoice/projects.ex`
- `lib/sitevoice_web/router.ex`
- `lib/sitevoice_web/components/nav_component.ex`
- `lib/sitevoice_web/components/core_components.ex`
- `lib/sitevoice_web/live/projects/show_live.ex`

## Design Tokens (from Slice 08)
- `--orange: #FF5C00`
- `--steel: #0E1117`
- `--steel-light: #1F2836`
- `--wire: #3D4F65`
- `--chalk: #C8D0DC`
- `--white: #EEF1F5`
- Font: Bebas Neue (display), DM Mono (labels), Barlow (body)

## Role Hierarchy
- `owner` — top of org, can do everything
- `org_admin` — can manage users, projects, memberships
- `pm` — can view users/memberships, add members to projects
- `foreman` — can only manage self

## Existing Patterns
- All LiveViews use `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- Ash calls: `tenant: socket.assigns.tenant`, `actor: socket.assigns.current_user`
- `organization_id` comes from `actor(:organization_id)` only — never from params
