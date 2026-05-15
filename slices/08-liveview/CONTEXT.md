# Context — Slice 08: LiveView Screens

## Dependency

Slice 07 (Notifications) must be complete before starting this slice.

## Purpose

This slice adds Phoenix LiveView screens that allow full end-to-end testing of the application
without requiring the mobile app. All core flows — registration, project management, recording
submission, pipeline monitoring, log review, and PM dashboard — are accessible from a browser.
It also ships the public marketing landing page at `/`.

Design reference mockups (open in browser to inspect):
- `docs/mockups/sitevoice-landing.html` — landing page and global design system
- `docs/mockups/sitevoice-mobile-ui.html` — recording flow screens (guides dashboard/processing UI)

## What To Read First

Load these files before touching any code:

1. `docs/APPLICATION_SPEC.md` §5 — DailyLog resource and actions (`:submit_recording`, `:approve_and_submit`)
2. `docs/APPLICATION_SPEC.md` §7 — AI Pipeline and pipeline step broadcasts
3. `docs/APPLICATION_SPEC.md` §8 — PDF generation and `pdf_url` calculation
4. `docs/APPLICATION_SPEC.md` §9 — Real-time: PubSub topic naming `"org:{org_id}:{resource}:{id}"`
5. `docs/CODING_STANDARDS.md` — LiveView conventions, file layout
6. `CLAUDE.md` — Architecture Rules §Multitenancy, Phoenix LiveView tenant propagation

## Design System

All UI must match the design language established in the mockups. Do not use default Phoenix or Tailwind styles — implement the custom CSS below.

### Color Tokens

```css
:root {
  --orange:      #FF5C00;
  --orange-hot:  #FF7A2F;
  --steel:       #0E1117;
  --steel-mid:   #161C27;
  --steel-light: #1F2836;
  --slate:       #2C3A4F;
  --wire:        #3D4F65;
  --chalk:       #C8D0DC;
  --white:       #EEF1F5;
  --yellow:      #FFB800;
  --green:       #22C55E;
  --red:         #EF4444;
}
```

### Typography

Load from Google Fonts:
```html
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@400;500&family=Barlow:ital,wght@0,400;0,600;0,700;1,400&display=swap" rel="stylesheet">
```

- `--font-display: 'Bebas Neue'` — page headings, large numbers, CTA copy
- `--font-mono: 'DM Mono'` — labels, tags, status text, meta info
- `--font-body: 'Barlow'` — body text, form fields, descriptions

### Visual Patterns

**Background:**
- Base: `var(--steel)` (`#0E1117`)
- Noise texture overlay at 3% opacity (see landing page `body::before` SVG filter)
- Blueprint grid on hero/large sections: `rgba(61,79,101,0.15)` 1px lines at 48px spacing

**Cards and surfaces:**
- Background: `var(--steel-light)` with `border: 1px solid var(--wire)`
- Border radius: 12–16px on cards, 6–8px on small elements
- Hover: background shifts to `var(--slate)`; top border becomes orange (`height: 2px; background: var(--orange)`)
- Orange left-border accent on highlighted text blocks: `border-left: 3px solid var(--orange); padding-left: 18px`

**Buttons:**
- Primary: `background: var(--orange)` + `clip-path: polygon(12px 0%, 100% 0%, calc(100% - 12px) 100%, 0% 100%)` (parallelogram shape)
- Ghost: `border-bottom: 1px solid var(--wire)` only; hover turns orange
- Hover: `background: var(--orange-hot)` and `transform: translateY(-2px)`

**Status pills:**
```css
/* Pending/warning */
.pill-pending { background: rgba(245,158,11,0.12); border: 1px solid rgba(245,158,11,0.3); color: var(--yellow); }
/* Success/done */
.pill-done    { background: rgba(34,197,94,0.12);  border: 1px solid rgba(34,197,94,0.3);  color: var(--green); }
/* Processing/active */
.pill-active  { background: rgba(255,92,0,0.12);   border: 1px solid rgba(255,92,0,0.3);   color: var(--orange); }
```

**Labels and section headers:**
- `font-family: var(--font-mono); font-size: 11px; letter-spacing: 3px; text-transform: uppercase; color: var(--orange)`
- Followed by a short orange `::after` rule (60px, 1px, orange at 50% opacity)

**Processing step list (dashboard / processing screen):**
- Done: `border-color: rgba(34,197,94,0.3)` + green icon
- Active: `border-color: rgba(255,92,0,0.4)` + orange icon + `●●●` badge animation
- Waiting: muted `var(--wire-light)` everything, `—` badge

**Navigation (global app nav, not landing nav):**
- Fixed top bar: `background: rgba(14,17,23,0.85); backdrop-filter: blur(12px); border-bottom: 1px solid var(--wire)`
- Logo: Bebas Neue, "Site**Voice**" with orange on "Voice"
- Nav links: monospace uppercase 13px; active/hover → `var(--orange)`

**Animations to include:**
- `fadeUp`: `opacity 0 → 1` + `translateY(30px → 0)` on page load
- `pulse`: for live recording indicator dot
- `ripple`: for processing orb rings
- `blink`: for transcript cursor
- `float`: for hero badge elements

### Landing Page (one-to-one port)

The file `docs/mockups/sitevoice-landing.html` is the **authoritative design reference** for the landing page. The LiveView landing page at `/` must match it exactly in content and visual design:

- **Nav**: SiteVoice AI logo + Beta badge, links (How It Works, Features, Pricing), "Get Early Access" CTA button
- **Hero**: blueprint grid background + orange glow, display headline "SPEAK YOUR DAY. BUILD YOUR REPORT.", sub-copy, two CTAs, stats row (75% / 90s / 30s), phone mockup with floating badges
- **Social proof strip**: "Trusted by field teams at" + fake company logos (Turner, Skanska, Hensel Phelps, McCarthy, DPR)
- **How It Works**: 5-step grid with step numbers, icons, times, titles, descriptions
- **Features**: 9-card grid (Noise-Cancelling, Bilingual, AI-Structured, Photo Captioning, Approval Workflow, Procore Sync, Offline-First, Branded PDF, Claim-Ready)
- **Testimonial**: Ramiro V. quote
- **Pricing**: Pro ($29/mo) + Enterprise ($500/mo) cards
- **CTA section**: orange background, "STOP TYPING." headline
- **Footer**: logo, copyright, links

The landing page is a Phoenix controller page (not LiveView) — render it from `PageController` via a `.heex` template. Extract all CSS into `assets/css/landing.css` (or inline in the root layout if simpler).

## Existing State

### Auth (already working)
- `lib/sitevoice_web/live_user_auth.ex` — `on_mount` hooks: `:live_user_required`, `:live_user_optional`, `:live_no_user`
- `lib/sitevoice_web/router.ex` — `ash_authentication_live_session :authenticated_routes` block (empty — needs routes added)
- Sign-in and register routes already exist at `/sign-in` and `/register` (via AshAuthentication)
- `lib/sitevoice_web/controllers/page_controller.ex` — `home` action exists; needs a `landing` action (or repurpose `home`)

### Domain (all Ash actions available)
- `Sitevoice.Accounts.User` — `:read`, `:current_user` actions; `role` field (`:foreman`, `:pm`, `:admin`)
- `Sitevoice.Projects.Project` — `:read`, `:create`, `:update` actions
- `Sitevoice.Projects.ProjectMembership` — `:read`, `:create` actions; `role` field
- `Sitevoice.Reporting.DailyLog` — `:submit_recording`, `:approve_and_submit`, `:read` actions; `status` field (`:processing`, `:ready`, `:submitted`); `transcript`, `summary`, `work_items`, `safety_notes`, `weather` structured fields
- `Sitevoice.Reporting.Photo` — associated with `DailyLog`
- `Sitevoice.Reporting.Calculations.PdfUrl` — exposes `pdf_url` on `DailyLog`
- `Sitevoice.Reporting.Calculations.AudioUrl` — exposes `audio_url` on `DailyLog`

### Storage
- `lib/sitevoice/storage.ex` — `Sitevoice.Storage.upload/4`, `Sitevoice.Storage.presigned_url/2`

### PubSub Topics (from Slice 06)
- Pipeline step progress: `"org:{org_id}:daily_log:{log_id}"`, message `{:pipeline_step, step, status}`
- Report ready: `"org:{org_id}:daily_log:{log_id}"`, message `{:report_ready, log}`
- PM dashboard feed: `"org:{org_id}:logs"`, message `{:log_updated, log}`

### Components
- `lib/sitevoice_web/components/core_components.ex` — standard Phoenix components (flash, modal, table, etc.)

## New Files To Create

### Landing Page

- `lib/sitevoice_web/controllers/page_html/landing.html.heex` — exact port of `docs/mockups/sitevoice-landing.html`
- `assets/css/landing.css` — all landing page CSS (colors, fonts, layout)

### LiveViews

- `lib/sitevoice_web/live/dashboard_live.ex` — home after login; branches on user role
- `lib/sitevoice_web/live/projects/index_live.ex` — project list, create project form (PM/admin only)
- `lib/sitevoice_web/live/projects/show_live.ex` — project detail: members, recent logs list
- `lib/sitevoice_web/live/logs/new_live.ex` — audio + photo upload form, submit to pipeline
- `lib/sitevoice_web/live/logs/processing_live.ex` — real-time pipeline progress display
- `lib/sitevoice_web/live/logs/show_live.ex` — structured log view, PDF download, approve + submit
- `lib/sitevoice_web/live/logs/index_live.ex` — PM dashboard: real-time feed of all logs

### Shared CSS

- `assets/css/app_ui.css` — shared design tokens and component styles for all LiveView screens (tokens, nav, cards, pills, buttons, step list, animations)

Use inline `~H` sigil for templates (co-located in the LiveView module).

### Tests

- `test/sitevoice_web/live/dashboard_live_test.exs`
- `test/sitevoice_web/live/projects/index_live_test.exs`
- `test/sitevoice_web/live/logs/new_live_test.exs`
- `test/sitevoice_web/live/logs/show_live_test.exs`

## Existing Files To Modify

- `lib/sitevoice_web/router.ex`
  - Change `get "/"` to render the landing page
  - Add all LiveView routes inside `ash_authentication_live_session :authenticated_routes`
- `lib/sitevoice_web/controllers/page_controller.ex` — add `landing` action (or rename `home` to `landing`)
- `assets/css/app.css` — import `landing.css` and `app_ui.css`
- `lib/sitevoice_web/components/layouts/root.html.heex` — add Google Fonts link

## Tenant Propagation in LiveViews

In LiveView there is no plug pipeline. Tenant must be extracted from the current user in `mount/3`:

```elixir
def mount(_params, _session, socket) do
  org_id = socket.assigns.current_user.organization_id
  socket = assign(socket, :tenant, org_id)
  # every Ash call must receive: tenant: socket.assigns.tenant, actor: socket.assigns.current_user
  {:ok, socket}
end
```

Every Ash call in a LiveView must include `tenant: socket.assigns.tenant` and `actor: socket.assigns.current_user`.

## Key Constraints

- Module names use `Sitevoice` / `SitevoiceWeb` (lowercase v) — project convention
- `organization_id` is NEVER set from form params — always from `current_user.organization_id`
- Use `Phoenix.LiveView.allow_upload/3` for audio and photo file uploads
  - Audio: accept `~w(.m4a .mp3 .wav .ogg)`, max 50MB, max_entries: 1
  - Photos: accept `~w(.jpg .jpeg .png .heic)`, max 10MB, max_entries: 10
- All LiveView tests tagged `@moduletag slice: :liveview`
- Use `Phoenix.LiveViewTest` helpers (`live/2`, `element/2`, `render_click/1`, `render_submit/2`)
- `mix compile --warnings-as-errors` — zero warnings
- `require Ash.Query` wherever Ash.Query macros (like `filter/2`) are used
- The landing page must render identically to `docs/mockups/sitevoice-landing.html` — same copy, same layout, same animations
