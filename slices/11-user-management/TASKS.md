# Slice 11 — User Management — Tasks

## Backend

- [x] 1. Add `active` (boolean, default true) and `invited_at` (utc_datetime_usec, nullable) to `User` resource
- [x] 2. Generate and run Ash migration for `active` and `invited_at` columns
- [x] 3. Fix `:invite` action: remove `HashPassword` change, generate random password inline, set `invited_at`, add after_action to send invitation email
- [x] 4. Create `SendInvitationEmail` logic — handled in updated `SendPasswordResetEmail` (detects invitation vs reset by `invited_at`/`confirmed_at`)
- [x] 5. Add `:deactivate` and `:reactivate` update actions on User with policies (org_admin/owner only)
- [x] 6. Guard `sign_in_with_password` to reject users where `active == false`
- [x] 7. Add `list_for_project` read action to `ProjectMembership` that loads `:user`
- [x] 8. Expand `Accounts` domain code_interface: `list_users`, `invite_user`, `deactivate_user`, `reactivate_user`, `update_user_role`, `update_profile`, `change_password`, `remove_user`
- [x] 9. Expand `Projects` domain code_interface: `list_project_memberships`, `update_membership_role`, `remove_membership`

## Frontend — Settings

- [x] 10. Create `Settings.UsersLive` at `/settings/users` with user table, invite modal, role/status management
- [x] 11. Create `Settings.ProfileLive` at `/settings/profile` with name/language edit and password change
- [x] 12. Create `Settings.OrganizationLive` at `/settings/organization` with org name edit

## Frontend — Projects

- [x] 13. Enhance `Projects.ShowLive` members panel: show user name+email, add role dropdown, add remove button, improve add-member modal with org user list

## Routing & Nav

- [x] 14. Add `/settings/users`, `/settings/profile`, `/settings/organization` to authenticated routes in router
- [x] 15. Update `NavComponent` to include "Settings" link
