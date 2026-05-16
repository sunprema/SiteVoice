# Slice 11 — User Management

**Goal:** Deliver a professional, fully functional user management UI covering all common org-level
and project-level user administration flows. Admins can invite users via magic link, manage roles,
deactivate members, and control project membership. All users can manage their own profile.

## Design Acceptance Criteria
- Consistent with established design tokens (steel/orange/chalk palette, DM Mono labels, Bebas headings)
- Role badges: Owner=gold, Admin=purple, PM=blue, Foreman=gray
- Status badges: Active=green, Pending=amber (invited, not confirmed), Deactivated=red
- Modal overlays for invite/add forms (not separate pages)
- Confirm dialog before destructive actions (deactivate, remove)
- Nav updated with "Settings" link (visible to all roles)

## Acceptance Criteria

### Backend: User resource additions
- [ ] `active` boolean attribute on User (default true); deactivated users cannot sign in
- [ ] `invited_at` utc_datetime_usec attribute on User (set on invite, nil on normal register)
- [ ] `:invite` action: creates user with random password hash, sets `invited_at`, sends invitation email with "Set your password" magic link (reuses reset token flow)
- [ ] `:deactivate` update action: sets `active = false`; policy: org_admin/owner only
- [ ] `:reactivate` update action: sets `active = true`; policy: org_admin/owner only
- [ ] `sign_in_with_password` rejects deactivated users (active? check)
- [ ] Migration: adds `invited_at`, `active` columns to users table

### Backend: ProjectMembership additions
- [ ] `list_for_project` read action with `user` association loaded
- [ ] Domain code_interface functions for: `list_users`, `invite_user`, `deactivate_user`, `reactivate_user`, `update_user_role`, `remove_user`; `list_project_memberships`, `update_membership_role`, `remove_membership`

### Settings.UsersLive (`/settings/users`)
- [ ] Accessible to `org_admin` and `owner` only; others redirected to `/dashboard`
- [ ] Table: avatar initial (colored circle), name, email, role badge, status badge (Active/Pending/Deactivated), joined/invited date
- [ ] Search/filter bar: text search (name or email), filter by role, filter by status
- [ ] "Invite User" button → modal with: email, name, role selector, language selector
- [ ] Invite submits via `:invite` action; success closes modal + row appears in table
- [ ] Per-row role dropdown (org_admin/owner only): changes role inline via `:update_role`
- [ ] Per-row "Resend Invite" button: visible only for Pending users; retriggers invitation email
- [ ] Per-row "Deactivate" / "Reactivate" toggle with confirm prompt
- [ ] Cannot deactivate self; cannot change own role; cannot deactivate the last owner

### Settings.ProfileLive (`/settings/profile`)
- [ ] Accessible to all authenticated users
- [ ] Edit name and preferred language (English / Spanish); saves via `:update_profile`
- [ ] Change password section: current password + new + confirm fields; saves via `:change_password`
- [ ] Success flash on save; error messages on failure

### Settings.OrganizationLive (`/settings/organization`)
- [ ] Accessible to `org_admin` and `owner` only
- [ ] Edit org name; saves via `Organization :update`
- [ ] Shows org slug (read-only, DM Mono)
- [ ] Shows member count and plan tier badge

### Projects.ShowLive — Members tab (enhanced)
- [ ] Members list shows user name + email (not just "Member" placeholder)
- [ ] Per-row project role dropdown (org_admin/pm/owner): changes project role via `:update_role` on ProjectMembership
- [ ] Per-row "Remove" button with confirm prompt; calls `:remove_member`
- [ ] "Add Member" modal searches existing org users not already on project

### Nav
- [ ] "Settings" link added to nav (all roles); links to `/settings/profile`
- [ ] For org_admin/owner: nav "Settings" dropdown or sub-nav showing: Profile / Users / Organization
- [ ] Active state highlights correct section

### General
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:user_management` — all tests pass
