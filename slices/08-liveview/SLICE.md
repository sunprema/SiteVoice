# Slice 08 — LiveView Screens

**Goal:** Ship the public marketing landing page and add Phoenix LiveView screens that allow
full end-to-end testing of SiteVoice from a browser, without requiring the React Native mobile
app. Every core user flow must be reachable: register an org, create a project, upload an audio
recording, watch the pipeline process in real time, review the structured log, download the PDF,
and approve/submit it. All UI must match the design established in `docs/mockups/sitevoice-landing.html`
and `docs/mockups/sitevoice-mobile-ui.html`.

Use **svg-animations** skill for creating svg animations where required.

## Design Acceptance Criteria

These apply to every page in this slice — landing page and all LiveViews.

- [ ] Color tokens match exactly: `--orange: #FF5C00`, `--steel: #0E1117`, `--steel-light: #1F2836`, `--wire: #3D4F65`, `--chalk: #C8D0DC`, `--white: #EEF1F5` (full token list in CONTEXT.md)
- [ ] Fonts loaded: Bebas Neue (display), DM Mono (labels/meta), Barlow (body)
- [ ] Dark background (`var(--steel)`) with noise texture overlay on all pages
- [ ] Primary buttons use parallelogram clip-path: `clip-path: polygon(12px 0%, 100% 0%, calc(100% - 12px) 100%, 0% 100%)`
- [ ] Status pills use the three-state pattern: pending (yellow), active/processing (orange), done (green)
- [ ] Cards: `var(--steel-light)` background + `var(--wire)` border; top 2px orange bar appears on hover
- [ ] Section labels: DM Mono, 11px, 3px letter-spacing, uppercase, orange, with short orange `::after` line
- [ ] Global nav: frosted glass (`backdrop-filter: blur(12px)`), orange "Voice" in logo, uppercase monospace links
- [ ] `fadeUp` animation on page load for hero/content sections
- [ ] Responsive: nav collapses on mobile (<768px); hero stacks single-column

## Acceptance Criteria

### Landing Page (`GET /`)

- [ ] Renders the full landing page matching `docs/mockups/sitevoice-landing.html` exactly
- [ ] **Nav**: "SiteVoice AI" logo (orange on "Voice") + "Beta" badge, links: How It Works / Features / Pricing / Get Early Access CTA
- [ ] **Hero**: blueprint grid + orange radial glow background; headline "SPEAK YOUR DAY. BUILD YOUR REPORT."; sub-copy with orange left border; two CTAs (Start Free Trial + See How It Works); stats row (75% Time Saved / 90s To Dictate / 30s To Report); phone mockup with waveform, live transcript, report preview, and three floating badges ("Report Generated", "Sent to Procore", "LABOR / 12 workers on site")
- [ ] **Social proof strip**: "Trusted by field teams at" + Turner / Skanska / Hensel Phelps / McCarthy / DPR logos (blurred, 15% opacity)
- [ ] **How It Works**: 5-step bordered grid with step numbers (Bebas, 72px, wire color), icons, timestamps, titles, descriptions
- [ ] **Features**: 9-card grid with orange top-border hover effect: Noise-Cancelling Transcription, Bilingual Support, AI-Structured Log, Photo Auto-Captioning, Approval Workflow, Procore & ACC Sync, Offline-First Mode, Branded PDF Reports, Claim-Ready Records
- [ ] **Testimonial**: Ramiro V. quote with large orange `"` character (Bebas, 200px, 8% opacity)
- [ ] **Pricing**: Pro ($29/mo per foreman) + Enterprise ($500/mo per project, "MOST POPULAR" badge) side-by-side
- [ ] **CTA section**: orange background, "STOP TYPING." headline, "SITEVOICE" watermark text, two CTA buttons
- [ ] **Footer**: logo + copyright + Privacy / Terms / Contact links
- [ ] All animations present: `ripple` on record button, `wave` on waveform bars, `blink` on transcript cursor, `float` on badges, `pulse` on hero tag dot
- [ ] "Get Early Access" and CTA buttons link to `/register`; "Sign In" links to `/sign-in`

### Routes

- [ ] `GET /` → landing page (unauthenticated; logged-in users see same page with nav updated to show "Dashboard" link)
- [ ] `GET /dashboard` → `DashboardLive` (authenticated; redirects to `/sign-in` if not logged in)
- [ ] `GET /projects` → `Projects.IndexLive` (authenticated)
- [ ] `GET /projects/:id` → `Projects.ShowLive` (authenticated)
- [ ] `GET /projects/:project_id/logs/new` → `Logs.NewLive` (authenticated)
- [ ] `GET /logs/:id/processing` → `Logs.ProcessingLive` (authenticated)
- [ ] `GET /logs/:id` → `Logs.ShowLive` (authenticated)
- [ ] `GET /logs` → `Logs.IndexLive` (authenticated)

### DashboardLive (`/dashboard`)

- [ ] Redirects to `/sign-in` if no authenticated user
- [ ] **Foreman view**: greeting ("Good [time of day], [name]"), today's log status card with pending/processing/ready/submitted pill, quick stats row (streak, total reports), recent reports list, large orange "RECORD DAY" button (linking to new recording)
- [ ] **PM/Admin view**: count of today's logs across all projects with status breakdown, link to `/logs` dashboard
- [ ] Design mirrors `#screen-home` from `docs/mockups/sitevoice-mobile-ui.html` (blueprint grid background, orange glow, status card, stats row, report list, big FAB button)

### Projects.IndexLive (`/projects`)

- [ ] Lists all projects the current user is a member of (via `ProjectMembership`), newest first
- [ ] PM/Admin: shows "New Project" button (parallelogram style, orange) that opens an inline form
- [ ] "New Project" form: name + code fields with DM Mono labels; submits via `Project :create` with `tenant: org_id`
- [ ] New project appears in list without page reload
- [ ] Each project card: `var(--steel-light)` background, project name in Bebas display font, code in DM Mono, member count

### Projects.ShowLive (`/projects/:id`)

- [ ] Shows project name (Bebas, large), code badge (DM Mono), and member count
- [ ] Lists recent `DailyLog` records for the project (status pill, date, foreman name, arrow chevron)
- [ ] PM/Admin: shows "Add Member" form (email + role select)
- [ ] Each log row links to `/logs/:id` (if ready/submitted) or `/logs/:id/processing` (if processing)

### Logs.NewLive (`/projects/:project_id/logs/new`)

- [ ] Audio upload: `allow_upload :audio`, accepts `.m4a .mp3 .wav .ogg`, max 50MB, 1 entry max
- [ ] Photos upload: `allow_upload :photos`, accepts `.jpg .jpeg .png .heic`, max 10MB, up to 10 entries
- [ ] Photo strip: thumbnail placeholders with orange border on filled slots, dashed "+" add slot (matches `docs/mockups/sitevoice-mobile-ui.html` photo strip)
- [ ] Upload progress shown per file
- [ ] "Submit Recording" button: consumes uploads, stores audio to Tigris at `{org_id}/audio/{filename}`, calls `DailyLog :submit_recording`, redirects to `/logs/:id/processing`
- [ ] Validates: audio entry required before enabling submit button

### Logs.ProcessingLive (`/logs/:id/processing`)

- [ ] Subscribes to `"org:{org_id}:daily_log:{log_id}"` PubSub topic on mount
- [ ] Central orb animation: three concentric rotating rings (speeds 2s / 3s / 4.5s, alternating directions) around an orange center icon — matches `docs/mockups/sitevoice-mobile-ui.html` `#screen-processing`
- [ ] Step list below orb: Audio Uploaded → Transcription → Structuring → Photo Captioning → PDF Generation
  - Done: green checkmark icon, `border-color: rgba(34,197,94,0.3)`
  - Active: orange icon, `border-color: rgba(255,92,0,0.4)`, animated `●●●` badge
  - Waiting: muted wire color, `—` badge
- [ ] When `{:report_ready, log}` received: shows "Report Ready" green banner + link to `/logs/:id`
- [ ] If log already `:ready` or `:submitted` on mount, show "Report Ready" immediately

### Logs.ShowLive (`/logs/:id`)

- [ ] Loads `DailyLog` with structured fields: `transcript`, `summary`, `work_items`, `safety_notes`, `weather`
- [ ] Each category rendered as a card matching the review screen in `docs/mockups/sitevoice-mobile-ui.html`: colored dot + DM Mono category label + entry count + bulleted rows with icon + body text
- [ ] Category color dots: Labor (blue `#60A5FA`), Progress (green `#34D399`), Equipment (yellow `#F59E0B`), Materials (purple `#A78BFA`), Delays (red `#F87171`), Safety (green `#22C55E`)
- [ ] "AI confidence" / completeness banner (green, with checkmark icon) when all categories present
- [ ] "Download PDF" link using `pdf_url` calculation (presigned Tigris URL); hidden if no pdf_url
- [ ] PM/Admin: "Approve & Submit" parallelogram button → calls `:approve_and_submit` → green success flash
- [ ] Success confirmation matches the success overlay in `docs/mockups/sitevoice-mobile-ui.html`: green border card with "REPORT SENT" in Bebas, delivery confirmations (PDF emailed, Procore, archived)

### Logs.IndexLive (`/logs`) — PM Dashboard

- [ ] Subscribes to `"org:{org_id}:logs"` PubSub topic on mount
- [ ] Lists all `DailyLog` records for the org (across all projects), newest first
- [ ] Columns: date, project name, foreman name, status pill, action link (chevron arrow)
- [ ] When `{:log_updated, log}` received: updates the matching row in real time
- [ ] Filter bar: DM Mono labels, filter by project and/or status

### General

- [ ] All LiveViews use `on_mount {SitevoiceWeb.LiveUserAuth, :live_user_required}`
- [ ] All Ash calls pass `tenant: socket.assigns.tenant` and `actor: socket.assigns.current_user`
- [ ] `organization_id` is never read from params or form data
- [ ] Global app nav (all authenticated screens): frosted glass bar with SiteVoice AI logo, role-appropriate links (Dashboard / Projects / Logs / Sign Out)
- [ ] `mix compile --warnings-as-errors` — zero warnings
- [ ] `mix test --only slice:liveview` — all tests pass
- [ ] `mix test` — no regressions in slices 00–07

## What This Slice Does NOT Include

- Mobile-specific native UX (file upload replaces native recording on web)
- Push notification UI (mobile only, Slice 10)
- Full admin management panel
- User profile or password change screens
- Procore or third-party integration UI (Slice 09)
- Audio recording directly in the browser via MediaRecorder (file upload only)
