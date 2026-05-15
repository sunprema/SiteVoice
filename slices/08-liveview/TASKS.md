# Tasks — Slice 08: LiveView Screens

Work through in order. Check off each task as it is completed.

---

## 1. Set Up Design System CSS

### 1a. Add Google Fonts

File: `lib/sitevoice_web/components/layouts/root.html.heex`

- [x] Add `<link rel="preconnect" href="https://fonts.googleapis.com">` to `<head>`
- [x] Add `<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@400;500&family=Barlow:ital,wght@0,400;0,600;0,700;1,400&display=swap" rel="stylesheet">` to `<head>`

### 1b. Create App UI CSS

File: `assets/css/app_ui.css`

- [x] CSS custom properties (full token set from CONTEXT.md Design System section)
- [x] Global reset: `*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }`
- [x] Body: `background: var(--steel); color: var(--chalk); font-family: var(--font-body);`
- [x] Noise texture overlay: `body::before` with SVG fractalNoise filter at 3% opacity, `position: fixed; inset: 0; pointer-events: none; z-index: 9999`
- [x] App nav styles: fixed top bar, backdrop-filter blur, logo, links
- [x] Card styles: `.card` base + hover state with orange top border
- [x] Button styles: `.btn-primary` (parallelogram + orange), `.btn-ghost` (border-bottom only), `.btn-secondary` (steel-light)
- [x] Status pill styles: `.pill-pending` (yellow), `.pill-active` (orange), `.pill-done` (green)
- [x] Section label styles: `.section-label` (DM Mono, orange, uppercase, letter-spacing)
- [x] Processing step styles: `.proc-step` base, `.proc-step.done`, `.proc-step.active`, `.proc-step.waiting`
- [x] Processing orb animation: `.orb-ring` with `spin` keyframe (three speeds: 2s, 3s, 4.5s)
- [x] Animations: `fadeUp`, `pulse`, `ripple`, `wave`, `blink`, `float`
- [x] Responsive breakpoint at 768px

### 1c. Import CSS

File: `assets/css/app.css`

- [x] Add `@import "app_ui.css";` and `@import "landing.css";`

---

## 2. Build Landing Page

### 2a. Port HTML

File: `lib/sitevoice_web/controllers/page_html/landing.html.heex`

- [x] Port `docs/mockups/sitevoice-landing.html` to HEEx verbatim
- [x] Replace `href="#"` on CTA buttons: "Get Early Access" → `href={~p"/register"}`, "Start Free Trial" → `href={~p"/register"}`, "Book a Demo" → `href={~p"/register"}`, "Start Free — No Card Needed" → `href={~p"/register"}`
- [x] Replace `href="#"` on sign-in nav link (if present) → `href={~p"/sign-in"}`
- [x] Keep all SVG, CSS class names, and inline styles identical to the mockup
- [x] Phone mockup waveform bars: generate with inline `style="--h:Xpx; --d:Xs"` attributes (copy values from mockup)

### 2b. Create Landing CSS

File: `assets/css/landing.css`

- [x] Extract ALL CSS from `docs/mockups/sitevoice-landing.html` `<style>` block verbatim into this file
- [x] Verify no class name conflicts with `app_ui.css` (landing uses `.nav-logo`, `.hero`, `.step`, etc. — these are scoped to the landing layout)

### 2c. Wire Controller and Router

File: `lib/sitevoice_web/controllers/page_controller.ex`

- [x] Add (or rename existing `home` to) `landing` action that renders `"landing.html"`

File: `lib/sitevoice_web/router.ex`

- [x] Change `get "/", PageController, :home` → `get "/", PageController, :landing`

---

## 3. Add LiveView Routes to Router

File: `lib/sitevoice_web/router.ex`

- [x] Inside `ash_authentication_live_session :authenticated_routes`, add:
  - [x] `live "/dashboard", DashboardLive`
  - [x] `live "/projects", Projects.IndexLive`
  - [x] `live "/projects/:id", Projects.ShowLive`
  - [x] `live "/projects/:project_id/logs/new", Logs.NewLive`
  - [x] `live "/logs", Logs.IndexLive`
  - [x] `live "/logs/:id", Logs.ShowLive`
  - [x] `live "/logs/:id/processing", Logs.ProcessingLive`

---

## 4. Add App Nav Component

File: `lib/sitevoice_web/components/nav_component.ex`

- [x] Define `SitevoiceWeb.NavComponent` as a functional component (`def nav(assigns)`)
- [x] Accepts `current_user` assign (nil-safe for landing page if reused)
- [x] Renders frosted glass nav bar matching the app nav style in CONTEXT.md
- [x] Logo: `Site<span class="accent">Voice</span> AI` in Bebas Neue + "Beta" badge
- [x] Links: Dashboard (`/dashboard`), Projects (`/projects`), Logs (`/logs` — pm/admin only), Sign Out (`/sign-out`)
- [x] Include in `root.html.heex` only for authenticated routes (not the landing page, which has its own nav)

---

## 5. Build DashboardLive

File: `lib/sitevoice_web/live/dashboard_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: set `tenant` from `current_user.organization_id`
- [x] Foreman branch: query `DailyLog` for today's log for current user; assign `:today_log`, `:recent_logs` (last 5)
- [x] PM/Admin branch: count `DailyLog` for today across org by status; assign `:today_counts`
- [x] **Foreman template**: blueprint grid background + orange top glow; greeting section (DM Mono sub-label, Bebas name, project/role line); today's status card with status pill; stats row (days streak, total filed); recent reports list (each row: date, summary snippet, status pill, chevron); large orange "RECORD DAY" button → `/projects` to choose a project
- [x] **PM/Admin template**: greeting + count cards per status (Processing / Ready for Review / Submitted) + "View All Logs" link

---

## 6. Build Projects.IndexLive

File: `lib/sitevoice_web/live/projects/index_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: load `ProjectMembership` for current user with `:project` loaded; assign `:projects`, `show_form: false`
- [x] `handle_event "open_new_form"`: assign `show_form: true`
- [x] `handle_event "save_project"`: call `Project :create` with `tenant:` + `actor:`; prepend to `:projects`; assign `show_form: false`
- [x] Show "New Project" button only when `current_user.role in [:pm, :admin]`
- [x] Form fields: name (text input), code (text input); labels in DM Mono uppercase
- [x] Project card: Bebas project name, DM Mono code badge, member count, link to show page

---

## 7. Build Projects.ShowLive

File: `lib/sitevoice_web/live/projects/show_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: load `Project` by id with `tenant:` + `actor:`; load recent `DailyLog` records (last 30); load `ProjectMembership` with `:user` loaded
- [x] `handle_event "add_member"`: call `ProjectMembership :create` with email + role; reload memberships
- [x] Each log row: status pill, date, foreman name, chevron arrow; link to processing or show depending on status
- [x] "Add Member" form only shown to pm/admin

---

## 8. Build Logs.NewLive

File: `lib/sitevoice_web/live/logs/new_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: set tenant; `allow_upload :audio` (`.m4a .mp3 .wav .ogg`, 50MB, 1 entry); `allow_upload :photos` (`.jpg .jpeg .png .heic`, 10MB, 10 entries)
- [x] Photo strip UI: filled thumbnails with orange border + photo number; dashed "+" add slot (matches mobile mockup)
- [x] `handle_event "validate"`: updates upload entry state (for live progress)
- [x] `handle_event "submit"`:
  - [x] Consume audio upload → Tigris at `{org_id}/audio/{uuid}-{filename}` via `Sitevoice.Storage.store_audio/2`
  - [x] Consume photo uploads → Tigris at `{org_id}/photos/{uuid}-{filename}` each
  - [x] Call `DailyLog :submit_recording` with `audio_key`, `project_id`, `tenant:`, `actor:`
  - [x] On success: `push_navigate` to `/logs/:id/processing`
- [x] Disable submit button when no audio entry present
- [x] Show per-file progress percentage via `entry.progress`

---

## 9. Build Logs.ProcessingLive

File: `lib/sitevoice_web/live/logs/processing_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: load `DailyLog` by id; if status `:draft` or `:submitted` → assign `report_ready: true`; else subscribe to `"org:{org_id}:log:{log_id}"`
- [x] Assign `step_statuses: %{"transcribed" => :waiting, "structured" => :waiting, "pdf_generated" => :waiting}`
- [x] `handle_info({:pipeline_update, %{step: step, status: :complete}}, socket)`: update matching step in `step_statuses`
- [x] `handle_info({:report_ready, _payload}, socket)`: assign `report_ready: true`
- [x] **Orb animation**: three rotating rings (CSS `spin` keyframe at 2s/3s/4.5s, middle ring reversed) around orange center icon — implement via CSS classes `.orb-ring.ring1/ring2/ring3` in `app_ui.css`
- [x] **Step list**: 5 steps matching mobile mockup; done = green check icon; active = orange table icon + animated `●●●` badge; waiting = wire color `—`
- [x] "Report Ready" green banner + "View Report →" link when `report_ready: true`

---

## 10. Build Logs.ShowLive

File: `lib/sitevoice_web/live/logs/show_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: load `DailyLog` by id with `load: [:pdf_url, :audio_url]`; assign `:log`
- [x] **Accuracy/completeness banner**: green banner when all 6 category fields present
- [x] **Category cards**: Labor (blue dot), Progress (green dot), Equipment (yellow dot), Materials (purple dot), Delays (red dot), Safety (green dot) — each card: header with dot + DM Mono label + count; body rows with icon + text
- [x] "Download PDF" `<a>` with `target="_blank"` using `@log.pdf_url`; hidden if nil
- [x] `handle_event "approve_submit"`: call `DailyLog :approve_and_submit`; reload log; assign `show_success: true`
- [x] **Success overlay** when `show_success: true`: green border card, "REPORT SENT" in Bebas, three delivery confirmation rows (PDF emailed, Procore, archived) — matches mobile success overlay
- [x] "Approve & Submit" button: shown only to org_admin when `log.status == :draft`

---

## 11. Build Logs.IndexLive (PM Dashboard)

File: `lib/sitevoice_web/live/logs/index_live.ex`

- [x] `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [x] `mount/3`: subscribe to `"org:{org_id}:logs"`; load all `DailyLog` records newest-first with `[:project, :foreman]`; assign `:logs`, `:filter_project_id`, `:filter_status`
- [x] `handle_info({:log_updated, log}, socket)`: replace matching log in list
- [x] `handle_event "filter"`: re-query with filters
- [x] Render: table rows (date, project name, foreman name, status pill, chevron link); filter bar (DM Mono labels, select inputs)

---

## 12. Write Tests

### Landing Page

File: `test/sitevoice_web/controllers/page_controller_test.exs`

- [x] Tag `@moduletag slice: :liveview`
- [x] Test `GET /` returns 200 with "SPEAK" in body
- [x] Test CTA links to `/register`

### DashboardLive

File: `test/sitevoice_web/live/dashboard_live_test.exs`

- [x] Tag `@moduletag slice: :liveview`
- [x] Test unauthenticated redirect to `/sign-in`
- [x] Test foreman view: shows today's log status pill and "RECORD DAY" button
- [x] Test PM view: shows today's log count / "Dashboard" heading

### Projects.IndexLive

File: `test/sitevoice_web/live/projects/index_live_test.exs`

- [x] Tag `@moduletag slice: :liveview`
- [x] Test project list renders for authenticated user
- [x] Test "New Project" form creates project and updates list (PM only)
- [x] Test foreman cannot see "New Project" button

### Logs.NewLive

File: `test/sitevoice_web/live/logs/new_live_test.exs`

- [x] Tag `@moduletag slice: :liveview`
- [x] Test form renders with upload inputs
- [x] Test submit without audio shows validation / disabled state

### Logs.ShowLive

File: `test/sitevoice_web/live/logs/show_live_test.exs`

- [x] Tag `@moduletag slice: :liveview`
- [x] Test log category cards display
- [x] Test "Approve & Submit" not visible to foreman
- [x] Test success overlay appears after approve action

---

## 13. Verify

- [x] `mix compile --warnings-as-errors` — zero warnings
- [ ] Open `http://localhost:4000/` in browser — landing page matches `docs/mockups/sitevoice-landing.html` visually
- [x] Open `http://localhost:4000/dashboard` — redirects to sign-in when not logged in (test passes)
- [x] Log in as foreman — dashboard shows today's status and "RECORD DAY" button (test passes)
- [x] Log in as PM — dashboard shows log counts (test passes)
- [x] `mix test --only slice:liveview` — all 14 tests pass
- [x] `mix test` — no regressions in slices 00–07 (114 tests, 0 failures)
