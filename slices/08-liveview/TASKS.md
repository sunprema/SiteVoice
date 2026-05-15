# Tasks — Slice 08: LiveView Screens

Work through in order. Check off each task as it is completed.

---

## 1. Set Up Design System CSS

### 1a. Add Google Fonts

File: `lib/sitevoice_web/components/layouts/root.html.heex`

- [ ] Add `<link rel="preconnect" href="https://fonts.googleapis.com">` to `<head>`
- [ ] Add `<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@400;500&family=Barlow:ital,wght@0,400;0,600;0,700;1,400&display=swap" rel="stylesheet">` to `<head>`

### 1b. Create App UI CSS

File: `assets/css/app_ui.css`

- [ ] CSS custom properties (full token set from CONTEXT.md Design System section)
- [ ] Global reset: `*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }`
- [ ] Body: `background: var(--steel); color: var(--chalk); font-family: var(--font-body);`
- [ ] Noise texture overlay: `body::before` with SVG fractalNoise filter at 3% opacity, `position: fixed; inset: 0; pointer-events: none; z-index: 9999`
- [ ] App nav styles: fixed top bar, backdrop-filter blur, logo, links
- [ ] Card styles: `.card` base + hover state with orange top border
- [ ] Button styles: `.btn-primary` (parallelogram + orange), `.btn-ghost` (border-bottom only), `.btn-secondary` (steel-light)
- [ ] Status pill styles: `.pill-pending` (yellow), `.pill-active` (orange), `.pill-done` (green)
- [ ] Section label styles: `.section-label` (DM Mono, orange, uppercase, letter-spacing)
- [ ] Processing step styles: `.proc-step` base, `.proc-step.done`, `.proc-step.active`, `.proc-step.waiting`
- [ ] Processing orb animation: `.orb-ring` with `spin` keyframe (three speeds: 2s, 3s, 4.5s)
- [ ] Animations: `fadeUp`, `pulse`, `ripple`, `wave`, `blink`, `float`
- [ ] Responsive breakpoint at 768px

### 1c. Import CSS

File: `assets/css/app.css`

- [ ] Add `@import "app_ui.css";` and `@import "landing.css";`

---

## 2. Build Landing Page

### 2a. Port HTML

File: `lib/sitevoice_web/controllers/page_html/landing.html.heex`

- [ ] Port `docs/mockups/sitevoice-landing.html` to HEEx verbatim
- [ ] Replace `href="#"` on CTA buttons: "Get Early Access" → `href={~p"/register"}`, "Start Free Trial" → `href={~p"/register"}`, "Book a Demo" → `href={~p"/register"}`, "Start Free — No Card Needed" → `href={~p"/register"}`
- [ ] Replace `href="#"` on sign-in nav link (if present) → `href={~p"/sign-in"}`
- [ ] Keep all SVG, CSS class names, and inline styles identical to the mockup
- [ ] Phone mockup waveform bars: generate with inline `style="--h:Xpx; --d:Xs"` attributes (copy values from mockup)

### 2b. Create Landing CSS

File: `assets/css/landing.css`

- [ ] Extract ALL CSS from `docs/mockups/sitevoice-landing.html` `<style>` block verbatim into this file
- [ ] Verify no class name conflicts with `app_ui.css` (landing uses `.nav-logo`, `.hero`, `.step`, etc. — these are scoped to the landing layout)

### 2c. Wire Controller and Router

File: `lib/sitevoice_web/controllers/page_controller.ex`

- [ ] Add (or rename existing `home` to) `landing` action that renders `"landing.html"`

File: `lib/sitevoice_web/router.ex`

- [ ] Change `get "/", PageController, :home` → `get "/", PageController, :landing`

---

## 3. Add LiveView Routes to Router

File: `lib/sitevoice_web/router.ex`

- [ ] Inside `ash_authentication_live_session :authenticated_routes`, add:
  - [ ] `live "/dashboard", DashboardLive`
  - [ ] `live "/projects", Projects.IndexLive`
  - [ ] `live "/projects/:id", Projects.ShowLive`
  - [ ] `live "/projects/:project_id/logs/new", Logs.NewLive`
  - [ ] `live "/logs", Logs.IndexLive`
  - [ ] `live "/logs/:id", Logs.ShowLive`
  - [ ] `live "/logs/:id/processing", Logs.ProcessingLive`

---

## 4. Add App Nav Component

File: `lib/sitevoice_web/components/nav_component.ex`

- [ ] Define `SitevoiceWeb.NavComponent` as a functional component (`def nav(assigns)`)
- [ ] Accepts `current_user` assign (nil-safe for landing page if reused)
- [ ] Renders frosted glass nav bar matching the app nav style in CONTEXT.md
- [ ] Logo: `Site<span class="accent">Voice</span> AI` in Bebas Neue + "Beta" badge
- [ ] Links: Dashboard (`/dashboard`), Projects (`/projects`), Logs (`/logs` — pm/admin only), Sign Out (`/auth/sign-out`)
- [ ] Include in `root.html.heex` only for authenticated routes (not the landing page, which has its own nav)

---

## 5. Build DashboardLive

File: `lib/sitevoice_web/live/dashboard_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: set `tenant` from `current_user.organization_id`
- [ ] Foreman branch: query `DailyLog` for today's log for current user; assign `:today_log`, `:recent_logs` (last 5)
- [ ] PM/Admin branch: count `DailyLog` for today across org by status; assign `:today_counts`
- [ ] **Foreman template**: blueprint grid background + orange top glow; greeting section (DM Mono sub-label, Bebas name, project/role line); today's status card with status pill; stats row (days streak, total filed); recent reports list (each row: date, summary snippet, status pill, chevron); large orange "RECORD DAY" button → `/projects` to choose a project
- [ ] **PM/Admin template**: greeting + count cards per status (Processing / Ready for Review / Submitted) + "View All Logs" link

---

## 6. Build Projects.IndexLive

File: `lib/sitevoice_web/live/projects/index_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: load `ProjectMembership` for current user with `:project` loaded; assign `:projects`, `show_form: false`
- [ ] `handle_event "open_new_form"`: assign `show_form: true`
- [ ] `handle_event "save_project"`: call `Project :create` with `tenant:` + `actor:`; prepend to `:projects`; assign `show_form: false`
- [ ] Show "New Project" button only when `current_user.role in [:pm, :admin]`
- [ ] Form fields: name (text input), code (text input); labels in DM Mono uppercase
- [ ] Project card: Bebas project name, DM Mono code badge, member count, link to show page

---

## 7. Build Projects.ShowLive

File: `lib/sitevoice_web/live/projects/show_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: load `Project` by id with `tenant:` + `actor:`; load recent `DailyLog` records (last 30); load `ProjectMembership` with `:user` loaded
- [ ] `handle_event "add_member"`: call `ProjectMembership :create` with email + role; reload memberships
- [ ] Each log row: status pill, date, foreman name, chevron arrow; link to processing or show depending on status
- [ ] "Add Member" form only shown to pm/admin

---

## 8. Build Logs.NewLive

File: `lib/sitevoice_web/live/logs/new_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: set tenant; `allow_upload :audio` (`.m4a .mp3 .wav .ogg`, 50MB, 1 entry); `allow_upload :photos` (`.jpg .jpeg .png .heic`, 10MB, 10 entries)
- [ ] Photo strip UI: filled thumbnails with orange border + photo number; dashed "+" add slot (matches mobile mockup)
- [ ] `handle_event "validate"`: updates upload entry state (for live progress)
- [ ] `handle_event "submit"`:
  - [ ] Consume audio upload → Tigris at `{org_id}/audio/{uuid}-{filename}` via `Sitevoice.Storage.upload/4`
  - [ ] Consume photo uploads → Tigris at `{org_id}/photos/{uuid}-{filename}` each
  - [ ] Call `DailyLog :submit_recording` with `audio_key`, `project_id`, `tenant:`, `actor:`
  - [ ] On success: `push_navigate` to `/logs/:id/processing`
- [ ] Disable submit button when no audio entry present
- [ ] Show per-file progress percentage via `entry.progress`

---

## 9. Build Logs.ProcessingLive

File: `lib/sitevoice_web/live/logs/processing_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: load `DailyLog` by id; if status `:ready` or `:submitted` → assign `report_ready: true`; else subscribe to `"org:{org_id}:daily_log:{log_id}"`
- [ ] Assign `step_statuses: %{transcription: :pending, structuring: :pending, photo_captioning: :pending, pdf_generation: :pending}`
- [ ] `handle_info({:pipeline_step, step, status}, socket)`: update matching step in `step_statuses`
- [ ] `handle_info({:report_ready, _log}, socket)`: assign `report_ready: true`
- [ ] **Orb animation**: three rotating rings (CSS `spin` keyframe at 2s/3s/4.5s, middle ring reversed) around orange center icon — implement via CSS classes `.orb-ring.ring1/ring2/ring3` in `app_ui.css`
- [ ] **Step list**: 5 steps matching mobile mockup; done = green check icon; active = orange table icon + animated `●●●` badge; waiting = wire color `—`
- [ ] "Report Ready" green banner + "View Report →" link when `report_ready: true`

---

## 10. Build Logs.ShowLive

File: `lib/sitevoice_web/live/logs/show_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: load `DailyLog` by id with `load: [:pdf_url, :audio_url]`; assign `:log`
- [ ] **Accuracy/completeness banner**: green banner when all 6 category fields present
- [ ] **Category cards**: Labor (blue dot), Progress (green dot), Equipment (yellow dot), Materials (purple dot), Delays (red dot), Safety (green dot) — each card: header with dot + DM Mono label + count; body rows with icon + text
- [ ] "Download PDF" `<a>` with `target="_blank"` using `@log.pdf_url`; hidden if nil
- [ ] `handle_event "approve_submit"`: call `DailyLog :approve_and_submit`; reload log; assign `show_success: true`
- [ ] **Success overlay** when `show_success: true`: green border card, "REPORT SENT" in Bebas, three delivery confirmation rows (PDF emailed, Procore, archived) — matches mobile success overlay
- [ ] "Approve & Submit" button: shown only to pm/admin and only when `log.status == :ready`

---

## 11. Build Logs.IndexLive (PM Dashboard)

File: `lib/sitevoice_web/live/logs/index_live.ex`

- [ ] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] `mount/3`: subscribe to `"org:{org_id}:logs"`; load all `DailyLog` records newest-first with `[:project, :foreman]`; assign `:logs`, `:filter_project_id`, `:filter_status`
- [ ] `handle_info({:log_updated, log}, socket)`: replace matching log in list
- [ ] `handle_event "filter"`: re-query with filters
- [ ] Render: table rows (date, project name, foreman name, status pill, chevron link); filter bar (DM Mono labels, select inputs)

---

## 12. Write Tests

### Landing Page

File: `test/sitevoice_web/controllers/page_controller_test.exs`

- [ ] Tag `@moduletag slice: :liveview`
- [ ] Test `GET /` returns 200 with "SPEAK YOUR DAY" in body
- [ ] Test "Get Early Access" links to `/register`

### DashboardLive

File: `test/sitevoice_web/live/dashboard_live_test.exs`

- [ ] Tag `@moduletag slice: :liveview`
- [ ] Test unauthenticated redirect to `/sign-in`
- [ ] Test foreman view: shows today's log status pill and "RECORD DAY" button
- [ ] Test PM view: shows today's log count

### Projects.IndexLive

File: `test/sitevoice_web/live/projects/index_live_test.exs`

- [ ] Tag `@moduletag slice: :liveview`
- [ ] Test project list renders for authenticated user
- [ ] Test "New Project" form creates project and updates list (PM only)
- [ ] Test foreman cannot see "New Project" button

### Logs.NewLive

File: `test/sitevoice_web/live/logs/new_live_test.exs`

- [ ] Tag `@moduletag slice: :liveview`
- [ ] Test form renders with upload inputs
- [ ] Test submit without audio shows validation / disabled state
- [ ] Test successful upload redirects to processing page (stub Tigris with `Req.Test`)

### Logs.ShowLive

File: `test/sitevoice_web/live/logs/show_live_test.exs`

- [ ] Tag `@moduletag slice: :liveview`
- [ ] Test log category cards display
- [ ] Test "Approve & Submit" visible to PM when log status is `:ready`
- [ ] Test "Approve & Submit" not visible to foreman
- [ ] Test success overlay appears after approve action

---

## 13. Verify

- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] Open `http://localhost:4000/` in browser — landing page matches `docs/mockups/sitevoice-landing.html` visually
- [ ] Open `http://localhost:4000/dashboard` — redirects to sign-in when not logged in
- [ ] Log in as foreman — dashboard shows today's status and "RECORD DAY" button
- [ ] Log in as PM — dashboard shows log counts; `/logs` shows PM dashboard with real-time updates
- [ ] `mix test --only slice:liveview` — all tests pass
- [ ] `mix test` — no regressions in slices 00–07
