# APPLICATION_SPEC.md

# SiteVoice AI — Technical Application Specification

**Version:** 1.1
**Status:** MVP Specification
**Last Updated:** May 2025
**Product:** SiteVoice AI — AI-powered construction daily log generation from voice memos
**Changelog v1.1:** Added full Ash multitenancy (attribute/row-level strategy) throughout all sections.

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [User Personas](#2-user-personas)
3. [System Architecture](#3-system-architecture)
4. [Technology Stack](#4-technology-stack)
5. [Domain Model](#5-domain-model)
6. [Multitenancy](#6-multitenancy)
7. [API Specification](#7-api-specification)
8. [Mobile Application](#8-mobile-application)
9. [Backend Services](#9-backend-services)
10. [AI Pipeline](#10-ai-pipeline)
11. [Real-time Communication](#11-real-time-communication)
12. [File Storage](#12-file-storage)
13. [PDF Generation](#13-pdf-generation)
14. [Authentication & Authorization](#14-authentication--authorization)
15. [External Integrations](#15-external-integrations)
16. [Offline Mode](#16-offline-mode)
17. [Data Schema](#17-data-schema)
18. [Infrastructure & Deployment](#18-infrastructure--deployment)
19. [Security](#19-security)
20. [Non-Functional Requirements](#20-non-functional-requirements)
21. [Architecture Decision Records](#21-architecture-decision-records)
22. [Phased Roadmap](#22-phased-roadmap)

---

## 1. Product Overview

SiteVoice AI transforms unstructured field voice memos into professional, structured construction daily logs. Foremen dictate their day in 90 seconds; the system produces an industry-standard daily report in under 30 seconds.

### Core Value Proposition

- **Foreman:** Eliminates 30–60 minutes of end-of-shift paperwork. Speak naturally, get a professional report.
- **Project Manager:** Consistent, structured daily logs with reliable data for budget and schedule tracking.
- **Owner/Developer:** High-level visibility into site progress and safety compliance.
- **Legal:** Timestamped, archived, PDF/A-standard reports defensible in delay claims.

### Key Metrics (MVP Targets)

| Metric                      | Target                                   |
| --------------------------- | ---------------------------------------- |
| Time saved per report       | > 75% reduction (from ~45 min to ~2 min) |
| End-to-end processing time  | < 30 seconds                             |
| Report completion rate      | > 95% of working days                    |
| AI accuracy (low edit rate) | < 10% of generated text requires editing |
| Uptime                      | 99.5%                                    |
| Tenant data isolation       | Zero cross-tenant data leakage           |

---

## 2. User Personas

### 2.1 Foreman (Primary)

- On-site, physically active during use
- Dislikes paperwork; needs hands-off reporting
- May be bilingual (English/Spanish)
- Uses Android or iOS smartphone
- Often in areas with poor or no connectivity (basements, remote sites)
- Belongs to one Organization (tenant)

### 2.2 Project Manager (Secondary)

- Office-based; receives completed reports
- Needs accurate, consistent data to track budget and schedule
- Uses reports to defend against delay claims
- Accesses web dashboard for project-wide visibility
- Belongs to one Organization (tenant)

### 2.3 Owner / Developer (Tertiary)

- Wants high-level progress and safety compliance visibility
- Typically accesses summary dashboards, not individual logs
- Belongs to one Organization (tenant)

### 2.4 Organization Admin

- Manages users, projects, and integrations within their tenant
- Invites foremen and PMs; manages billing tier
- Cannot access other organizations' data

---

## 3. System Architecture

For full system architecture, component diagrams, data flow diagrams,
process boundary map, and design rationale, see:

**→ `docs/ARCHITECTURE.md`**

### Summary

- **Mobile:** React Native + Expo (iOS/Android)
- **Backend:** Phoenix + Elixir on Fly.io
- **Domain layer:** Ash Framework (attribute multitenancy, organization_id)
- **Pipeline:** Ash Reactor (Whisper → Claude → Imprintor → Tigris)
- **Database:** PostgreSQL (Fly.io managed)
- **Storage:** Tigris (org-prefixed S3-compatible)
- **Real-time:** Phoenix Channels + PubSub (org-namespaced topics)
- **Jobs:** Oban (Postgres-backed, org_id in all args)

Processing time: audio upload → PDF ready in **< 30 seconds**.

## 4. Technology Stack

### 4.1 Full Stack

| Layer                            | Technology                                        | Version                     | Rationale                               |
| -------------------------------- | ------------------------------------------------- | --------------------------- | --------------------------------------- |
| **Mobile**                       | React Native + Expo                               | RN 0.74+                    | Cross-platform iOS/Android              |
| **Live Transcription (display)** | `@react-native-voice/voice`                       | Latest                      | On-device STT for real-time UI          |
| **Audio Recording**              | `expo-av`                                         | Latest                      | High-quality audio capture              |
| **Backend Framework**            | Phoenix + Elixir                                  | Elixir 1.17+ / Phoenix 1.7+ | OTP concurrency, real-time              |
| **Domain Layer**                 | Ash Framework                                     | 3.x                         | Declarative resources, policies         |
| **Multitenancy**                 | Ash attribute strategy                            | Built-in                    | Row-level, organization_id scoping      |
| **DSL Extensions**               | Spark DSL                                         | Latest                      | Custom Ash extensions                   |
| **Pipeline Orchestration**       | Ash Reactor                                       | Latest                      | Supervised async step pipelines         |
| **API Generation**               | AshJsonApi                                        | Latest                      | JSON:API from resource definitions      |
| **Authorization**                | Ash Policies                                      | Built-in                    | Declarative, tenant-aware               |
| **Audit Trail**                  | Ash Paper Trail                                   | Latest                      | Per-tenant change history               |
| **Authentication**               | AshAuthentication                                 | Latest                      | JWT with organization_id claim          |
| **Job Queue**                    | Oban                                              | 2.x                         | Postgres-backed; org_id in all job args |
| **Transcription**                | OpenAI Whisper API (`whisper-1`)                  | v1                          | MVP; migrate to self-hosted later       |
| **AI Structuring**               | Anthropic Claude API (`claude-sonnet-4-20250514`) | Latest                      | Structured output, 6 categories         |
| **Database**                     | PostgreSQL + AshPostgres                          | PG 16+                      | Row-level multitenancy; org_id indexes  |
| **File Storage**                 | Tigris (S3-compatible)                            | —                           | Global CDN; org-prefixed key paths      |
| **S3 Client**                    | `ex_aws` + `ex_aws_s3`                            | Latest                      | Tigris S3-compatible API                |
| **PDF Generation**               | Imprintor (Typst + Rust)                          | 0.6.x                       | Native Elixir, no external container    |
| **HTTP Client**                  | `Req`                                             | Latest                      | API calls to OpenAI, Anthropic          |
| **Email**                        | Swoosh                                            | Latest                      | Native Elixir email                     |
| **Real-time**                    | Phoenix Channels + PubSub                         | Built-in                    | Org-namespaced topics                   |

### 4.2 Future (Post-MVP)

| Layer                | Technology                                                     | Trigger                                                    |
| -------------------- | -------------------------------------------------------------- | ---------------------------------------------------------- |
| Transcription        | Self-hosted Whisper (Rust NIF, `whisper-rs`, `large-v3-turbo`) | First Enterprise client or 200+ foremen                    |
| Noise pre-processing | `dasp` Rust crate (via NIF)                                    | When accuracy complaints arise                             |
| GraphQL API          | AshGraphQL                                                     | If PM dashboard requires complex queries                   |
| Schema-per-tenant    | Ash context strategy                                           | If Enterprise client requires contractual schema isolation |

---

## 5. Domain Model

### 5.1 Ash Domains

```
SiteVoice.Accounts      → Organization (global), User (tenanted), Token (global)
SiteVoice.Projects      → Project (tenanted), ProjectMembership (tenanted)
SiteVoice.Reporting     → DailyLog (tenanted), Photo (tenanted)
SiteVoice.Integrations  → Integration (tenanted), IntegrationEvent (tenanted)
SiteVoice.Admin         → cross-tenant resources for platform admins only
```

### 5.2 Tenant Root — `SiteVoice.Accounts.Organization`

The Organization **is** the tenant. It is NOT itself tenanted — it lives in global scope.

```elixir
# No multitenancy block — this IS the tenant root
attributes:
  - id:           :uuid (primary key)
  - name:         :string   (e.g. "Turner Construction West")
  - slug:         :string   (unique globally, URL-safe)
  - tier:         :atom     [:pro, :enterprise]
  - active:       :boolean
  - inserted_at, updated_at

relationships:
  - has_many :users
  - has_many :projects
  - has_many :integrations
```

### 5.3 Tenanted Resources

All resources below declare `multitenancy strategy :attribute, attribute :organization_id`.

#### `SiteVoice.Accounts.User`

```elixir
multitenancy: strategy :attribute, attribute :organization_id

attributes:
  - id:                 :uuid
  - organization_id:    :uuid (NOT NULL → organizations.id)
  - email:              :string (unique within organization)
  - hashed_password:    :string
  - role:               :atom [:foreman, :pm, :owner, :org_admin]
  - name:               :string
  - preferred_language: :atom [:en, :es]
  - inserted_at, updated_at

relationships:
  - belongs_to :organization
  - has_many   :daily_logs
  - has_many   :project_memberships
```

#### `SiteVoice.Projects.Project`

```elixir
multitenancy: strategy :attribute, attribute :organization_id

attributes:
  - id:              :uuid
  - organization_id: :uuid (NOT NULL)
  - name:            :string
  - code:            :string (unique within organization)
  - address:         :string
  - timezone:        :string
  - active:          :boolean
  - inserted_at, updated_at

relationships:
  - belongs_to :organization
  - has_many   :daily_logs
  - has_many   :project_memberships
  - has_many   :integrations
```

#### `SiteVoice.Reporting.DailyLog` (Core Resource)

```elixir
multitenancy: strategy :attribute, attribute :organization_id

attributes:
  - id:              :uuid
  - organization_id: :uuid (NOT NULL)
  - date:            :date
  - status:          :atom [:pending, :processing, :draft, :submitted, :failed]
  - audio_key:       :string  (Tigris key — org-prefixed)
  - audio_duration:  :integer (seconds)
  - transcript:      :string
  - pdf_key:         :string  (Tigris key — org-prefixed)
  - accuracy_score:  :float
  - weather:         :string  (optional)
  - labor:           {:array, :map}
  - progress:        {:array, :map}
  - equipment:       {:array, :map}
  - materials:       {:array, :map}
  - delays:          {:array, :map}
  - safety:          {:array, :map}
  - submitted_at:    :utc_datetime
  - inserted_at, updated_at

relationships:
  - belongs_to :organization
  - belongs_to :foreman, SiteVoice.Accounts.User
  - belongs_to :project, SiteVoice.Projects.Project
  - has_many   :photos

actions:
  - :submit_recording   (create)
  - :apply_transcript   (update → status: :processing)
  - :apply_structure    (update → status: :draft)
  - :approve_and_submit (update → status: :submitted)
  - :mark_failed        (update → status: :failed)
  - :read, :destroy
```

#### `SiteVoice.Reporting.Photo`

```elixir
multitenancy: strategy :attribute, attribute :organization_id

attributes:
  - id:              :uuid
  - organization_id: :uuid (NOT NULL)
  - storage_key:     :string  (Tigris key — org-prefixed)
  - caption:         :string  (AI-generated)
  - category:        :atom    [:progress, :equipment, :delays, :safety, :materials]
  - taken_at:        :utc_datetime
  - inserted_at, updated_at

relationships:
  - belongs_to :organization
  - belongs_to :daily_log
```

#### `SiteVoice.Integrations.Integration`

```elixir
multitenancy: strategy :attribute, attribute :organization_id

attributes:
  - id:              :uuid
  - organization_id: :uuid (NOT NULL)
  - provider:        :atom [:procore, :autodesk_acc, :slack, :email]
  - config:          :map  (encrypted at rest)
  - active:          :boolean
  - inserted_at, updated_at
```

### 5.4 Global (Non-Tenanted) Resources

| Resource                          | Reason                          |
| --------------------------------- | ------------------------------- |
| `SiteVoice.Accounts.Organization` | IS the tenant root              |
| `SiteVoice.Accounts.Token`        | Auth tokens — scoped by user FK |

---

## 6. Multitenancy

### 6.1 Strategy Decision

**Ash attribute-based multitenancy (row-level isolation).**

Every tenanted resource carries an `organization_id` column. AshPostgres automatically appends `WHERE organization_id = $1` to every query when a tenant is active in the Ash context. No manual scoping anywhere in application code.

See ADR 005 for the decision rationale and migration path.

### 6.2 Ash Resource Declaration

Every tenanted resource includes this block:

```elixir
defmodule SiteVoice.Reporting.DailyLog do
  use Ash.Resource,
    domain: SiteVoice.Reporting,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshPaperTrail.Resource]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "daily_logs"
    repo  SiteVoice.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    # ... remaining attributes
  end
end
```

### 6.3 SetTenant Plug — HTTP Requests

```elixir
# lib/site_voice_web/plugs/set_tenant.ex
defmodule SiteVoiceWeb.Plugs.SetTenant do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{organization_id: org_id} when not is_nil(org_id) ->
        assign(conn, :current_tenant, org_id)
      _ ->
        conn
    end
  end
end

# lib/site_voice_web/router.ex
pipeline :api do
  plug :accepts, ["json"]
  plug SiteVoiceWeb.Plugs.VerifyToken    # sets current_user
  plug SiteVoiceWeb.Plugs.SetTenant      # must come after VerifyToken
end
```

### 6.4 JWT Claims

```elixir
# AshAuthentication token config
authentication do
  tokens do
    enabled?             true
    token_resource       SiteVoice.Accounts.Token
    signing_secret       Application.fetch_env!(:site_voice, :token_signing_secret)
    access_token_expiry  :timer.hours(24)
    refresh_token_expiry :timer.days(30)
    extra_token_fields   [:organization_id]    # ← included in every JWT
  end
end
```

JWT payload:

```json
{
  "sub": "user-uuid",
  "organization_id": "org-uuid",
  "role": "foreman",
  "exp": 1234567890
}
```

`organization_id` is **never** accepted from client request bodies — only sourced from the verified JWT.

### 6.5 Oban Jobs — Tenant Propagation

Oban workers run in separate BEAM processes. Tenant context does not propagate automatically. **Every job arg must include `organization_id`.**

```elixir
# Enqueueing — always pass organization_id explicitly
defmodule SiteVoice.Reporting.Changes.EnqueueProcessing do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _cs, log ->
      %{log_id: log.id, organization_id: log.organization_id}
      |> SiteVoice.Workers.AudioProcessor.new()
      |> Oban.insert()
      {:ok, log}
    end)
  end
end

# Worker — re-establishes tenant as first action
defmodule SiteVoice.Workers.AudioProcessor do
  use Oban.Worker, queue: :audio, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}) do
# pass tenant to every Ash call

    %{log_id: log_id, organization_id: org_id}
    |> SiteVoice.Reporting.Reactors.ProcessRecording.run()
    |> case do
      {:ok, _}    -> :ok
      {:error, e} -> {:error, e}
    end
  end
end
```

### 6.6 Ash Reactor — Tenant Propagation

`organization_id` is a first-class Reactor input. A `SetTenant` step runs before all Ash steps.

```elixir
defmodule SiteVoice.Reporting.Reactors.ProcessRecording do
  use Ash.Reactor

  input :log_id
  input :organization_id

  step :set_tenant, SiteVoice.Steps.SetTenant do
    argument :organization_id, input(:organization_id)
  end

  step :fetch_log, SiteVoice.Steps.FetchLog do
    argument :log_id, input(:log_id)
    wait_for :set_tenant    # all Ash steps wait for tenant to be set
  end

  # ... remaining steps
end

# lib/site_voice/reporting/steps/set_tenant.ex
defmodule SiteVoice.Steps.SetTenant do
  use Reactor.Step

  def run(%{organization_id: org_id}, _, _) do
# pass tenant to every Ash call
    {:ok, org_id}
  end

  def compensate(_, _, _, _), do: :ok
end
```

### 6.7 Phoenix Channels — Tenant Propagation

Channel processes are long-lived. Tenant must be set on `join` and re-applied on every `handle_in`.

```elixir
defmodule SiteVoiceWeb.RecordingChannel do
  use Phoenix.Channel

  def join("recording:" <> log_id, _params, socket) do
    org_id = socket.assigns.current_user.organization_id
# pass tenant to every Ash call
    {:ok, assign(socket, organization_id: org_id, log_id: log_id)}
  end

  def handle_in("recording_complete", %{"log_id" => log_id}, socket) do
# pass tenant to every Ash call

    %{log_id: log_id, organization_id: socket.assigns.organization_id}
    |> SiteVoice.Workers.AudioProcessor.new()
    |> Oban.insert()

    push(socket, "processing_started", %{})
    {:noreply, socket}
  end
end
```

### 6.8 PubSub — Org-Namespaced Topics

All topics prefixed with `org:{org_id}:` — no bare resource topics allowed.

```elixir
# Correct
"org:#{org_id}:log:#{log_id}"
"org:#{org_id}:project:#{project_id}"

# Never — cross-tenant leak risk
"log:#{log_id}"
"project:#{project_id}"

# Broadcasting from a Reactor step
defmodule SiteVoice.Steps.BroadcastReady do
  use Reactor.Step

  def run(%{log_id: log_id, organization_id: org_id, pdf_url: url}, _, _) do
    Phoenix.PubSub.broadcast(
      SiteVoice.PubSub,
      "org:#{org_id}:log:#{log_id}",
      {:report_ready, %{log_id: log_id, pdf_url: url}}
    )
    {:ok, :sent}
  end
end
```

### 6.9 Organization Registration Flow

Registration is the only flow outside tenant context — it creates the Organization (tenant root) and the first `org_admin` user atomically.

```elixir
defmodule SiteVoice.Accounts.Actions.RegisterOrganization do
  use Ash.Action

  def run(input, _) do
    Ash.Transaction.run(fn ->
      {:ok, org} = Ash.create(Organization, %{
        name: input.org_name,
        slug: Slug.slugify(input.org_name),
        tier: :pro
      })

      {:ok, user} = Ash.create(User, %{
        organization_id: org.id,
        email:           input.email,
        password:        input.password,
        name:            input.name,
        role:            :org_admin
      })

      {:ok, %{organization: org, user: user}}
    end)
  end
end
```

### 6.10 Admin Access (Cross-Tenant)

Platform admins use a separate `SiteVoice.Admin` domain with no multitenancy block. Never exposed via the public AshJsonApi router.

```elixir
defmodule SiteVoice.Admin.DailyLog do
  use Ash.Resource,
    domain: SiteVoice.Admin,
    data_layer: AshPostgres.DataLayer
  # No multitenancy block — sees all rows
  # Policy: platform admin role only
end
```

### 6.11 Tenant Isolation Checklist

Make sure tenant is passed for every Ash call.

---

## 7. API Specification

### 7.1 REST API (AshJsonApi — JSON:API spec)

Base URL: `https://api.sitevoice.app/api`

All endpoints require `Authorization: Bearer <jwt>` except auth routes.
All tenanted endpoints are implicitly scoped to the organization in the JWT.
Clients never pass `organization_id` in request bodies.

#### Organization (Registration & Onboarding)

```
POST   /organizations         Register new org + first org_admin user
GET    /organizations/me      Get current user's organization
PATCH  /organizations/me      Update org name
```

#### Authentication

```
POST   /auth/register         Invite user into current org (org_admin only)
POST   /auth/sign-in          Email + password → JWT (includes organization_id)
POST   /auth/refresh          Refresh access token
DELETE /auth/sign-out         Invalidate token
```

#### Daily Logs (tenant-scoped)

```
GET    /daily-logs            List logs (filter: project, date, status)
GET    /daily-logs/:id        Get single log with all sections
POST   /daily-logs            Submit recording → Reactor pipeline
PATCH  /daily-logs/:id        Approve / edit sections
DELETE /daily-logs/:id        Delete (foreman only, pre-submission)
```

#### Projects (tenant-scoped)

```
GET    /projects              List projects
GET    /projects/:id          Get project + recent log summary
POST   /projects              Create (org_admin / pm only)
PATCH  /projects/:id          Update
```

#### Photos

```
POST   /daily-logs/:id/photos Upload photos
GET    /daily-logs/:id/photos List photos
DELETE /photos/:id            Delete photo
```

### 7.2 Request / Response Examples

#### Register Organization

```json
POST /organizations
{
  "data": {
    "type": "organization",
    "attributes": {
      "org_name": "Turner Construction West",
      "email":    "admin@turner-west.com",
      "password": "...",
      "name":     "James Turner"
    }
  }
}
```

Response: JWT with `organization_id` claim, ready for all subsequent calls.

#### Submit Recording

```json
POST /daily-logs
Authorization: Bearer <jwt>

{
  "data": {
    "type": "daily_log",
    "attributes": {
      "date":           "2025-05-14",
      "audio_key":      "org-uuid/proj-uuid/2025-05-14/log-uuid.m4a",
      "audio_duration": 87
    },
    "relationships": {
      "project": { "data": { "type": "project", "id": "proj-uuid" } }
    }
  }
}
```

`organization_id` is never in the request body — extracted from JWT by `SetTenant` plug.

#### Response — Draft Report

```json
{
  "data": {
    "type": "daily_log",
    "id": "log-uuid",
    "attributes": {
      "status": "draft",
      "date": "2025-05-14",
      "accuracy_score": 0.96,
      "transcript": "North wall framing is about 80% complete...",
      "labor": [
        {
          "crew": "Martinez",
          "headcount": 6,
          "trade": "Rebar",
          "hours": "07:00-16:00"
        },
        {
          "crew": "Apex Electric",
          "headcount": 2,
          "trade": "Electrical rough-in",
          "hours": "08:00-16:00"
        }
      ],
      "progress": [
        {
          "description": "North wall framing ~80% complete",
          "location": "Level 4"
        },
        {
          "description": "Level 3 rebar layout completed, ready for inspection",
          "location": "Level 3"
        }
      ],
      "equipment": [
        { "item": "Crane 1", "status": "operational" },
        {
          "item": "Crane 2",
          "status": "offline",
          "note": "Hydraulic issue, resolved 12:00 PM"
        }
      ],
      "materials": [
        {
          "item": "Concrete 4000 PSI",
          "quantity": "8 yards",
          "received_at": "14:00"
        }
      ],
      "delays": [
        {
          "description": "Crane 2 offline AM — ~3 hours lost",
          "impact": "Level 4 framing schedule"
        }
      ],
      "safety": [
        {
          "description": "Toolbox talk completed. No incidents. PPE check 07:15."
        }
      ]
    }
  }
}
```

---

## 8. Mobile Application

### 8.1 Tech Dependencies

```json
{
  "expo": "~51.0.0",
  "react-native": "0.74.x",
  "@react-native-voice/voice": "^3.2.4",
  "expo-av": "~14.0.0",
  "expo-file-system": "~17.0.0",
  "expo-image-picker": "~15.0.0",
  "expo-background-fetch": "~12.0.0",
  "expo-task-manager": "~11.0.0",
  "@react-native-async-storage/async-storage": "^1.23.0",
  "phoenix": "^1.0.0",
  "react-native-mmkv": "^2.12.0"
}
```

### 8.2 Screen Flow

```
Splash / Auth
     │
     ▼
Home Dashboard
  ├── Today's report status (pending / draft / submitted)
  ├── Quick stats (workers, streak, total reports)
  ├── Recent report list
  └── [RECORD DAY] button
          │
          ▼
     Recording Screen
       ├── On-device STT (@rn-voice) → live transcript display
       ├── expo-av recording (high quality .m4a capture)
       ├── Photo capture strip
       ├── Tip chips (crew, equipment, deliveries, safety, delays)
       └── [STOP] button
                │
                ▼
          Processing Screen
            ├── Upload audio + photos → Tigris (via Phoenix API)
            ├── Reactor pipeline status via Channel
            └── Step-by-step progress display
                      │
                      ▼
              Review Screen
                ├── 6 category cards
                ├── Accuracy score
                ├── Photo thumbnails + AI captions
                ├── Inline editing
                ├── Warning flags
                └── [SUBMIT] / [SAVE DRAFT]
                          │
                          ▼
                  Success Screen
                    ├── PDF emailed to PM
                    ├── Pushed to Procore (if configured)
                    └── Archived in Tigris
```

### 8.3 Dual Audio Strategy

```javascript
// System A — On-device STT (live UI display only)
Voice.onSpeechPartialResults = (e) => setLiveTranscript(e.value[0]);
await Voice.start("en-US");

// System B — High-quality capture (sent to Whisper for final transcript)
const { recording } = await Audio.Recording.createAsync(
  Audio.RecordingOptionsPresets.HIGH_QUALITY,
);
```

### 8.4 Tenant Context on Mobile

JWT stored on device contains `organization_id`. Attached to every request as `Authorization: Bearer <token>` and passed when opening Phoenix Channel sockets. Mobile app never constructs tenant-scoped queries — all scoping is server-side.

```javascript
// Attach JWT to all API requests
const headers = {
  Authorization: `Bearer ${storage.getString("auth_token")}`,
  "Content-Type": "application/vnd.api+json",
};

// Pass to Phoenix Socket
const socket = new Socket("wss://api.sitevoice.app/socket", {
  params: { token: storage.getString("auth_token") },
});
```

### 8.5 Offline Queue

```javascript
async function queueOfflineRecording(logId, audioUri, metadata) {
  const queue = JSON.parse(storage.getString("offline_queue") || "[]");
  queue.push({
    logId,
    audioUri,
    metadata,
    token: storage.getString("auth_token"), // JWT carries org_id server-side
    queuedAt: Date.now(),
  });
  storage.set("offline_queue", JSON.stringify(queue));
}

BackgroundFetch.registerTaskAsync("SYNC_OFFLINE_RECORDINGS", async () => {
  const queue = JSON.parse(storage.getString("offline_queue") || "[]");
  if (!queue.length) return BackgroundFetch.BackgroundFetchResult.NoData;

  for (const item of queue) {
    const success = await uploadRecording(item);
    if (success) removeFromQueue(item.logId);
  }
  return BackgroundFetch.BackgroundFetchResult.NewData;
});
```

---

## 9. Backend Services

### 9.1 Ash Domain Structure

```elixir
defmodule SiteVoice.Accounts do
  use Ash.Domain
  resources do
    resource SiteVoice.Accounts.Organization  # global (tenant root)
    resource SiteVoice.Accounts.User          # tenanted
    resource SiteVoice.Accounts.Token         # global
  end
end

defmodule SiteVoice.Projects do
  use Ash.Domain
  resources do
    resource SiteVoice.Projects.Project            # tenanted
    resource SiteVoice.Projects.ProjectMembership  # tenanted
  end
end

defmodule SiteVoice.Reporting do
  use Ash.Domain
  resources do
    resource SiteVoice.Reporting.DailyLog  # tenanted
    resource SiteVoice.Reporting.Photo     # tenanted
  end
end

defmodule SiteVoice.Integrations do
  use Ash.Domain
  resources do
    resource SiteVoice.Integrations.Integration       # tenanted
    resource SiteVoice.Integrations.IntegrationEvent  # tenanted
  end
end

defmodule SiteVoice.Admin do
  use Ash.Domain
  # No multitenancy — platform admin only, never in public router
  resources do
    resource SiteVoice.Admin.Organization
    resource SiteVoice.Admin.DailyLog
  end
end
```

### 9.2 Oban Queues

```elixir
config :site_voice, Oban,
  repo: SiteVoice.Repo,
  queues: [
    audio:         10,
    ai:            5,
    pdf:           5,
    integrations:  10,
    notifications: 20
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [
      {"0 6 * * *", SiteVoice.Workers.DailyReminderWorker}
    ]}
  ]
```

# pass tenant to every Ash call

### 9.3 Ash Reactor — Full Pipeline Definition

```elixir
defmodule SiteVoice.Reporting.Reactors.ProcessRecording do
  use Ash.Reactor

  input :log_id
  input :organization_id

  step :set_tenant, SiteVoice.Steps.SetTenant do
    argument :organization_id, input(:organization_id)
  end

  step :fetch_log, SiteVoice.Steps.FetchLog do
    argument :log_id, input(:log_id)
    wait_for :set_tenant
  end

  step :fetch_audio, SiteVoice.Steps.FetchFromTigris do
    argument :key, result(:fetch_log, [:audio_key])
  end

  step :transcribe, SiteVoice.Steps.TranscribeWhisper do
    argument :audio,    result(:fetch_audio)
    argument :language, result(:fetch_log, [:foreman, :preferred_language])
  end

  ash_update :save_transcript, SiteVoice.Reporting.DailyLog do
    inputs %{transcript: result(:transcribe)}
    action :apply_transcript
    filter expr(id == ^input(:log_id))
  end

  # Steps 4 & 5 run concurrently
  step :structure, SiteVoice.Steps.StructureWithClaude do
    argument :transcript, result(:transcribe)
    async? true
  end

  step :caption_photos, SiteVoice.Steps.CaptionPhotos do
    argument :photo_keys, result(:fetch_log, [:photos])
    argument :transcript, result(:transcribe)
    async? true
  end

  ash_update :save_structure, SiteVoice.Reporting.DailyLog do
    inputs %{
      labor:          result(:structure, [:labor]),
      progress:       result(:structure, [:progress]),
      equipment:      result(:structure, [:equipment]),
      materials:      result(:structure, [:materials]),
      delays:         result(:structure, [:delays]),
      safety:         result(:structure, [:safety]),
      accuracy_score: result(:structure, [:accuracy_score])
    }
    action :apply_structure
    filter expr(id == ^input(:log_id))
  end

  step :generate_pdf, SiteVoice.Steps.GeneratePdf do
    argument :log, result(:save_structure)
  end

  step :store_pdf, SiteVoice.Steps.StoreTigris do
    argument :binary,          result(:generate_pdf)
    argument :key,             input(:log_id)
    argument :organization_id, input(:organization_id)
  end

  step :notify, SiteVoice.Steps.BroadcastReady do
    argument :log_id,          input(:log_id)
    argument :organization_id, input(:organization_id)
    argument :pdf_url,         result(:store_pdf, [:url])
  end

  compensate :save_transcript do
    ash_update SiteVoice.Reporting.DailyLog do
      inputs %{status: :pending}
      action :update
      filter expr(id == ^input(:log_id))
    end
  end
end
```

---

## 10. AI Pipeline

### 10.1 Transcription — OpenAI Whisper API

**Endpoint:** `POST https://api.openai.com/v1/audio/transcriptions`
**Model:** `whisper-1` | **Cost:** $0.006/min | **Max file:** 25MB

```elixir
defmodule SiteVoice.Steps.TranscribeWhisper do
  use Reactor.Step

  @construction_prompt """
  Construction site daily log. Foreman reporting end-of-shift.
  Common terms: rebar, BIM, HVAC, soffit, pour schedule, OSHA,
  subcontractor, footing, conduit, sheathing, curtain wall,
  means and methods, RFI, submittal, punchlist, change order.
  """

  def run(%{audio: audio_binary, language: lang}, _, _) do
    language = if lang == :es, do: "es", else: "en"

    Req.post("https://api.openai.com/v1/audio/transcriptions",
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      form_multipart: [
        file:            {"recording.m4a", audio_binary, content_type: "audio/m4a"},
        model:           "whisper-1",
        language:        language,
        prompt:          @construction_prompt,
        response_format: "json"
      ]
    )
    |> case do
      {:ok, %{status: 200, body: %{"text" => text}}} -> {:ok, text}
      {:ok, %{status: s, body: b}} -> {:error, "Whisper #{s}: #{inspect(b)}"}
      {:error, r} -> {:error, r}
    end
  end

  defp api_key, do: Application.fetch_env!(:site_voice, :openai_api_key)
end
```

**Bilingual:** `preferred_language: :es` → Whisper transcribes in Spanish → Claude outputs English. ES → EN translation is transparent.

### 10.2 Structuring — Anthropic Claude API

**Model:** `claude-sonnet-4-20250514`

```elixir
defmodule SiteVoice.Steps.StructureWithClaude do
  use Reactor.Step

  @system_prompt """
  You are an expert construction daily log assistant. Extract information
  from the transcript and return ONLY valid JSON with these keys:
  labor, progress, equipment, materials, delays, safety, accuracy_score.

  - labor:     [{crew, headcount, trade, hours, subcontractor}]
  - progress:  [{description, location, percentage_complete}]
  - equipment: [{item, status, note}]
  - materials: [{item, quantity, received_at, note}]
  - delays:    [{description, cause, impact, hours_lost}]
  - safety:    [{description, incident_type}]
  - accuracy_score: float 0.0–1.0

  Empty sections → []. Return ONLY JSON. No preamble. No fences.
  """

  def run(%{transcript: transcript}, _, _) do
    Req.post("https://api.anthropic.com/v1/messages",
      headers: [
        {"x-api-key",         api_key()},
        {"anthropic-version", "2023-06-01"},
        {"content-type",      "application/json"}
      ],
      json: %{
        model:    "claude-sonnet-4-20250514",
        max_tokens: 2000,
        system:   @system_prompt,
        messages: [%{role: "user", content: transcript}]
      }
    )
    |> parse_response()
  end

  defp parse_response({:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}}) do
    case Jason.decode(t) do
      {:ok, data} -> {:ok, Map.new(data, fn {k, v} -> {String.to_atom(k), v} end)}
      {:error, _} -> {:error, "Invalid JSON from Claude: #{t}"}
    end
  end
  defp parse_response({:ok, %{status: s, body: b}}), do: {:error, "Claude #{s}: #{inspect(b)}"}
  defp parse_response({:error, r}),                  do: {:error, r}

  defp api_key, do: Application.fetch_env!(:site_voice, :anthropic_api_key)
end
```

### 10.3 Photo Captioning — Claude Vision

```elixir
defmodule SiteVoice.Steps.CaptionPhotos do
  use Reactor.Step

  def run(%{photo_keys: keys, transcript: transcript}, _, _) do
    photos = Enum.map(keys, fn key ->
      {:ok, binary} = SiteVoice.Storage.fetch(key)
      caption  = generate_caption(Base.encode64(binary), transcript)
      category = infer_category(caption)
      %{key: key, caption: caption, category: category}
    end)
    {:ok, photos}
  end

  defp generate_caption(b64, transcript) do
    body = %{
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [%{role: "user", content: [
        %{type: "image", source: %{type: "base64", media_type: "image/jpeg", data: b64}},
        %{type: "text",  text: """
          Construction site photo. Foreman context: #{String.slice(transcript, 0, 300)}.
          Write a single concise caption (max 15 words) for a daily construction log.
        """}
      ]}]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [{"x-api-key", api_key()}, {"anthropic-version", "2023-06-01"}]
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => t} | _]}}} -> String.trim(t)
      _ -> "Site photo"
    end
  end

  defp infer_category(caption) do
    cond do
      String.match?(caption, ~r/crack|issue|damage|delay|problem/i) -> :delays
      String.match?(caption, ~r/crane|equipment|machine/i)           -> :equipment
      String.match?(caption, ~r/safety|hazard|ppe|harness/i)         -> :safety
      String.match?(caption, ~r/material|delivery|concrete|rebar/i)  -> :materials
      true                                                            -> :progress
    end
  end

  defp api_key, do: Application.fetch_env!(:site_voice, :anthropic_api_key)
end
```

---

## 11. Real-time Communication

### 11.1 Phoenix Channel — Recording

```elixir
defmodule SiteVoiceWeb.RecordingChannel do
  use Phoenix.Channel

  def join("recording:" <> log_id, _params, socket) do
    org_id = socket.assigns.current_user.organization_id
# pass tenant to every Ash call
    if authorized?(socket, log_id) do
      {:ok, assign(socket, log_id: log_id, organization_id: org_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("recording_complete", %{"log_id" => log_id}, socket) do
# pass tenant to every Ash call
    %{log_id: log_id, organization_id: socket.assigns.organization_id}
    |> SiteVoice.Workers.AudioProcessor.new()
    |> Oban.insert()
    push(socket, "processing_started", %{})
    {:noreply, socket}
  end
end
```

### 11.2 Client Events Reference

| Direction       | Event                | Payload              |
| --------------- | -------------------- | -------------------- |
| Client → Server | `recording_complete` | `%{log_id}`          |
| Server → Client | `processing_started` | `%{}`                |
| Server → Client | `pipeline_update`    | `%{step, status}`    |
| Server → Client | `report_ready`       | `%{log_id, pdf_url}` |
| Server → Client | `pipeline_failed`    | `%{log_id, reason}`  |

---

## 12. File Storage

### 12.1 Tigris Configuration

```elixir
config :ex_aws,
  access_key_id:     System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region:            "auto",
  s3: [scheme: "https://", host: "fly.storage.tigris.dev", port: 443]
```

### 12.2 Org-Prefixed Key Structure

```
sitevoice-audio/  {organization_id}/{project_id}/{date}/{log_id}.m4a
sitevoice-photos/ {organization_id}/{project_id}/{log_id}/{photo_id}.jpg
sitevoice-pdfs/   {organization_id}/{project_id}/{year}/{month}/{log_id}.pdf
```

### 12.3 Storage Module

```elixir
defmodule SiteVoice.Storage do
  @audio_bucket "sitevoice-audio"
  @photo_bucket "sitevoice-photos"
  @pdf_bucket   "sitevoice-pdfs"

  def audio_key(org_id, project_id, date, log_id),
    do: "#{org_id}/#{project_id}/#{date}/#{log_id}.m4a"

  def photo_key(org_id, project_id, log_id, photo_id),
    do: "#{org_id}/#{project_id}/#{log_id}/#{photo_id}.jpg"

  def pdf_key(org_id, project_id, log_id) do
    d = Date.utc_today()
    "#{org_id}/#{project_id}/#{d.year}/#{d.month}/#{log_id}.pdf"
  end

  def store_audio(key, binary),
    do: put(@audio_bucket, key, binary, "audio/m4a")

  def store_pdf(key, binary),
    do: put(@pdf_bucket, key, binary, "application/pdf")

  def fetch(key, bucket \\ @audio_bucket) do
    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{body: b}} -> {:ok, b}
      {:error, r}       -> {:error, r}
    end
  end

  def presigned_url(bucket, key, expires_in \\ 3600),
    do: ExAws.S3.presigned_url(ExAws.config(), :get, bucket, key, expires_in: expires_in)

  defp put(bucket, key, binary, content_type) do
    ExAws.S3.put_object(bucket, key, binary,
      content_type: content_type,
      server_side_encryption: "AES256"
    ) |> ExAws.request()
  end
end
```

---

## 13. PDF Generation

### 13.1 Imprintor (Typst + Rust)

Imprintor generates PDFs from Typst templates via native Rust. Returns in-memory binary — no filesystem writes or external containers.

**PDF Standard:** `a-3a` (PDF/A archival — legally defensible)

```elixir
defmodule SiteVoice.Steps.GeneratePdf do
  use Reactor.Step

  def run(%{log: log}, _, _) do
    template = File.read!(
      Application.app_dir(:site_voice, "priv/templates/daily_log.typ")
    )

    data = %{
      "organization"   => log.organization.name,
      "project"        => log.project.name,
      "project_code"   => log.project.code,
      "date"           => Date.to_string(log.date),
      "foreman"        => log.foreman.name,
      "submitted_at"   => format_dt(log.submitted_at),
      "log_id"         => log.id,
      "labor"          => log.labor,
      "progress"       => log.progress,
      "equipment"      => log.equipment,
      "materials"      => log.materials,
      "delays"         => log.delays,
      "safety"         => log.safety,
      "photos"         => log.photos,
      "accuracy_score" => log.accuracy_score
    }

    config = Imprintor.Config.new(template, data, pdf_standard: "a-3a")

    case Imprintor.compile_to_pdf(config) do
      {:ok, binary}    -> {:ok, binary}
      {:error, reason} -> {:error, "PDF failed: #{reason}"}
    end
  end

  defp format_dt(nil), do: "—"
  defp format_dt(dt),  do: Calendar.strftime(dt, "%B %d, %Y %H:%M")
end
```

### 13.2 Typst Template

```typst
// priv/templates/daily_log.typ
#set document(title: "Daily Log — " + sys.inputs.elixir_data.date, date: datetime.today())
#set page(paper: "us-letter", margin: (x: 1.2in, y: 1in))
#set text(font: "Barlow", size: 10pt)

#grid(columns: (1fr, auto), [
  = #sys.inputs.elixir_data.project
  *Daily Site Log* — #sys.inputs.elixir_data.date \
  Org: #sys.inputs.elixir_data.organization · Code: #sys.inputs.elixir_data.project_code
],[
  #align(right)[
    Foreman: *#sys.inputs.elixir_data.foreman* \
    SiteVoice AI · #sys.inputs.elixir_data.submitted_at
  ]
])
#line(length: 100%)

== Labor
#for e in sys.inputs.elixir_data.labor [
  - *#e.crew* (#e.headcount workers) — #e.trade | #e.hours
]

== Progress
#for e in sys.inputs.elixir_data.progress [- #e.description]

// Equipment, Materials, Delays, Safety follow same pattern

#line(length: 100%, stroke: 0.5pt)
#text(size: 8pt, fill: gray)[SiteVoice AI · PDF/A-3a · #sys.inputs.elixir_data.log_id]
```

---

## 14. Authentication & Authorization

### 14.1 AshAuthentication

```elixir
defmodule SiteVoice.Accounts.User do
  use Ash.Resource, extensions: [AshAuthentication]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  authentication do
    strategies do
      password :password do
        identity_field :email
        hashed_with    Bcrypt
      end
    end
    tokens do
      enabled?             true
      token_resource       SiteVoice.Accounts.Token
      signing_secret       Application.fetch_env!(:site_voice, :token_signing_secret)
      access_token_expiry  :timer.hours(24)
      refresh_token_expiry :timer.days(30)
      extra_token_fields   [:organization_id]
    end
  end
end
```

### 14.2 Ash Policies

Policies express user-level rules. Tenant isolation (org scoping) is handled by multitenancy — policies never need to re-check `organization_id`.

```elixir
policies do
  policy action(:submit_recording) do
    authorize_if actor_attribute_equals(:role, :foreman)
  end

  policy action([:read, :apply_structure, :approve_and_submit]) do
    authorize_if relates_to_actor_via(:foreman)
    authorize_if actor_attribute_equals(:role, :pm)
    authorize_if actor_attribute_equals(:role, :org_admin)
  end

  policy action(:destroy) do
    forbid_if attribute_equals(:status, :submitted)
    authorize_if relates_to_actor_via(:foreman)
  end
end
```

### 14.3 Router Pipelines

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug SiteVoiceWeb.Plugs.VerifyToken    # AshAuthentication → sets current_user
# pass tenant to every Ash call
end

pipeline :admin do
  plug :accepts, ["json"]
  plug SiteVoiceWeb.Plugs.VerifyAdminToken  # platform admin only — no tenant set
end
```

---

## 15. External Integrations

### 15.1 Procore (Enterprise)

```elixir
defmodule SiteVoice.Integrations.Adapters.Procore do
  def push_daily_log(log, integration) do
    Req.post(
      "https://api.procore.com/rest/v1.0/projects/#{integration.external_project_id}/daily_logs",
      headers: [{"Authorization", "Bearer #{integration.access_token}"}],
      json: %{daily_log: %{
        log_date:   Date.to_string(log.date),
        notes:      format_notes(log),
        status:     "approved",
        created_by: log.foreman.name
      }}
    )
  end
end
```

### 15.2 Email (Swoosh)

```elixir
defmodule SiteVoice.Reporting.Emails.DailyLogEmail do
  import Swoosh.Email

  def report_ready(log, pdf_binary, pm) do
    new()
    |> to({pm.name, pm.email})
    |> from({"SiteVoice AI", "reports@sitevoice.app"})
    |> subject("Daily Log — #{log.project.name} · #{log.date}")
    |> text_body("Daily site report for #{log.date} is ready.")
    |> attachment(%Swoosh.Attachment{
        filename:     "daily-log-#{log.date}.pdf",
        content:      pdf_binary,
        content_type: "application/pdf"
      })
  end
end
```

### 15.3 Integration Roadmap

| Integration                 | Tier             | Status   |
| --------------------------- | ---------------- | -------- |
| Email (Swoosh)              | Pro + Enterprise | MVP      |
| Procore Daily Log API       | Enterprise       | MVP      |
| Autodesk Construction Cloud | Enterprise       | Post-MVP |
| Slack                       | Enterprise       | Post-MVP |
| Microsoft Teams             | Enterprise       | Post-MVP |

---

## 16. Offline Mode

### 16.1 Strategy

Offline mode is client-side only. The JWT stored on device carries `organization_id` — tenant context is re-established server-side from the token on upload. No special server logic required.

### 16.2 Client Queue

```javascript
async function queueOfflineRecording(logId, audioUri, metadata) {
  const queue = JSON.parse(storage.getString("offline_queue") || "[]");
  queue.push({
    logId,
    audioUri,
    metadata,
    token: storage.getString("auth_token"), // JWT → org_id restored server-side
    queuedAt: Date.now(),
  });
  storage.set("offline_queue", JSON.stringify(queue));
}

BackgroundFetch.registerTaskAsync("SYNC_OFFLINE_RECORDINGS", async () => {
  const queue = JSON.parse(storage.getString("offline_queue") || "[]");
  if (!queue.length) return BackgroundFetch.BackgroundFetchResult.NoData;

  for (const item of queue) {
    if (await uploadRecording(item)) removeFromQueue(item.logId);
  }
  return BackgroundFetch.BackgroundFetchResult.NewData;
});
```

---

## 17. Data Schema

### 17.1 PostgreSQL Tables

```sql
-- organizations (global — IS the tenant, no organization_id column)
CREATE TABLE organizations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL,
  tier        TEXT NOT NULL DEFAULT 'pro',
  active      BOOLEAN NOT NULL DEFAULT true,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- users (tenanted)
CREATE TABLE users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    UUID NOT NULL REFERENCES organizations(id),
  email              TEXT NOT NULL,
  hashed_password    TEXT NOT NULL,
  role               TEXT NOT NULL DEFAULT 'foreman',
  name               TEXT NOT NULL,
  preferred_language TEXT NOT NULL DEFAULT 'en',
  inserted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, email)    -- email unique within org only
);
CREATE INDEX idx_users_org ON users(organization_id);

-- projects (tenanted)
CREATE TABLE projects (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  code            TEXT NOT NULL,
  address         TEXT,
  timezone        TEXT NOT NULL DEFAULT 'America/Phoenix',
  active          BOOLEAN NOT NULL DEFAULT true,
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code)
);
CREATE INDEX idx_projects_org ON projects(organization_id);

-- daily_logs (tenanted)
CREATE TABLE daily_logs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  date            DATE NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',
  audio_key       TEXT,
  audio_duration  INTEGER,
  transcript      TEXT,
  pdf_key         TEXT,
  accuracy_score  FLOAT,
  labor           JSONB NOT NULL DEFAULT '[]',
  progress        JSONB NOT NULL DEFAULT '[]',
  equipment       JSONB NOT NULL DEFAULT '[]',
  materials       JSONB NOT NULL DEFAULT '[]',
  delays          JSONB NOT NULL DEFAULT '[]',
  safety          JSONB NOT NULL DEFAULT '[]',
  submitted_at    TIMESTAMPTZ,
  foreman_id      UUID NOT NULL REFERENCES users(id),
  project_id      UUID NOT NULL REFERENCES projects(id),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, date, foreman_id, project_id)
);

-- organization_id is the LEADING column on all indexes
CREATE INDEX idx_daily_logs_org_project_date
  ON daily_logs(organization_id, project_id, date DESC);
CREATE INDEX idx_daily_logs_org_foreman
  ON daily_logs(organization_id, foreman_id, date DESC);
CREATE INDEX idx_daily_logs_org_status
  ON daily_logs(organization_id, status);

-- photos (tenanted)
CREATE TABLE photos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  storage_key     TEXT NOT NULL,
  caption         TEXT,
  category        TEXT,
  taken_at        TIMESTAMPTZ,
  daily_log_id    UUID NOT NULL REFERENCES daily_logs(id) ON DELETE CASCADE,
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_photos_org_log ON photos(organization_id, daily_log_id);

-- integrations (tenanted)
CREATE TABLE integrations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  provider        TEXT NOT NULL,
  config          JSONB NOT NULL DEFAULT '{}',
  active          BOOLEAN NOT NULL DEFAULT true,
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, provider)
);
```

---

## 18. Infrastructure & Deployment

### 18.1 Services

| Service          | Platform                        | Notes                         |
| ---------------- | ------------------------------- | ----------------------------- |
| Phoenix App      | Fly.io                          | Multi-region, auto-scaling    |
| PostgreSQL       | Fly.io Postgres                 | Managed, daily backups        |
| File Storage     | Tigris                          | Global CDN, org-prefixed keys |
| Email            | Swoosh + Resend                 | Transactional                 |
| Error Monitoring | Sentry (Elixir SDK)             |                               |
| Metrics          | Fly.io built-in + LiveDashboard |                               |

### 18.2 Environment Variables

```bash
DATABASE_URL=postgresql://...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
SECRET_KEY_BASE=...
TOKEN_SIGNING_SECRET=...
PHX_HOST=api.sitevoice.app
RESEND_API_KEY=...
PROCORE_CLIENT_ID=...
PROCORE_CLIENT_SECRET=...
```

### 18.3 Fly.io Configuration

```toml
app = "sitevoice-api"
primary_region = "phx"

[[services]]
  internal_port = 4000
  protocol      = "tcp"
  [[services.ports]]
    port     = 443
    handlers = ["tls", "http"]

[env]
  PHX_HOST = "api.sitevoice.app"
  MIX_ENV  = "prod"

[[vm]]
  cpu_kind = "shared"
  cpus     = 2
  memory   = "1gb"
```

---

## 19. Security

### 19.1 Tenant Isolation

- Ash attribute multitenancy enforces `organization_id` at the database query layer — no application code can accidentally return cross-tenant data
- `organization_id` is never accepted from client request bodies — sourced only from verified JWT claims
- All Tigris storage keys are org-prefixed — logical isolation in shared buckets
- All PubSub topics are org-namespaced — no cross-tenant message delivery possible

### 19.2 Audio & Data Privacy

- All audio files encrypted at rest (AES-256) in Tigris
- Audio optionally deleted from Tigris post-transcription (configurable per organization)
- Transcripts and structured data in PostgreSQL only
- PDFs served via presigned Tigris URLs (1-hour expiry)
- No audio data written to application logs

### 19.3 API Security

- All API routes require JWT; `organization_id` from JWT only — never from request
- JWT access tokens: 24h; refresh tokens: 30 days
- Ash Policies enforce user-level rules on top of tenant isolation
- Rate limiting on auth endpoints (Hammer)
- HTTPS only; HSTS enforced

### 19.4 Secrets Management

- All secrets via environment variables, never hardcoded
- Fly.io secrets storage for production
- API keys rotated quarterly

---

## 20. Non-Functional Requirements

| Requirement                  | Target                        | Implementation                                                                |
| ---------------------------- | ----------------------------- | ----------------------------------------------------------------------------- |
| End-to-end processing time   | < 30 seconds                  | Concurrent Reactor steps (Claude + Vision parallel)                           |
| API response time (p95)      | < 200ms                       | AshJsonApi + org-leading Postgres indexes                                     |
| Uptime                       | 99.5%                         | Fly.io multi-region, OTP supervision                                          |
| Audio upload size            | 25MB max                      | Validated pre-upload                                                          |
| Concurrent recordings        | 500+                          | OTP process model, Oban                                                       |
| Offline queue                | Unlimited local               | MMKV + expo-file-system                                                       |
| PDF generation               | < 5 seconds                   | Imprintor native Rust, in-memory                                              |
| Audit trail                  | All changes                   | Ash Paper Trail (per tenant)                                                  |
| Data retention               | 7 years                       | Tigris lifecycle policy                                                       |
| **Tenant isolation**         | **Zero cross-tenant leakage** | **Ash attribute multitenancy + org-prefixed storage + org-namespaced PubSub** |
| **Tenant query performance** | **< 200ms at 1,000 orgs**     | **organization_id as leading column on all indexes**                          |

---

## 21. Architecture Decision Records

### ADR 001 — Ash Framework

**Status:** Accepted. Ash 3.x for all domain resources. AshPostgres, AshJsonApi, AshAuthentication, Ash Policies, Ash Paper Trail, Ash Reactor. No hand-written Ecto queries or Phoenix controllers for resources.

### ADR 002 — Tigris File Storage

**Status:** Accepted. S3-compatible, global CDN. All keys prefixed with `organization_id`. `ex_aws` + `ex_aws_s3` as client.

### ADR 003 — Whisper: Hosted API for MVP

**Status:** Accepted. OpenAI `whisper-1` for MVP. Migration trigger: first Enterprise client requiring on-premise audio, or monthly cost > $500. Change is isolated to one Reactor step.

### ADR 004 — Imprintor for PDF Generation

**Status:** Accepted. Imprintor (Typst + native Rust). In-memory binary. PDF/A-3a standard. No Gotenberg container.

### ADR 005 — Multitenancy: Attribute Strategy (Row-Level)

**Status:** Accepted.

**Decision:** Ash `strategy :attribute` with `organization_id` on all tenanted resources.

**Why over schema-per-tenant:**

- Single schema — simpler migrations and operations
- No per-tenant migration runner
- Admin cross-tenant queries are straightforward
- Sufficient isolation for Pro and Enterprise at MVP scale

**Consequences and rules:**

- `organization_id` in every Oban job arg — enforced by code review

# pass tenant to every Ash call

- Tigris keys org-prefixed
- PubSub topics org-namespaced
- All Postgres indexes: `organization_id` as leading column

**Migration trigger to schema-per-tenant:** Enterprise client contractually requires schema isolation (e.g. government, defence). Ash context strategy supports this but requires significant migration effort.

### ADR 006 — JSON:API for Mobile, GraphQL Deferred

**Status:** Accepted. AshJsonApi for mobile REST. AshGraphQL deferred to Phase 2 for PM dashboard if needed. Both coexist in Ash with no conflict.

---

## 22. Phased Roadmap

### Phase 1 — MVP (Months 1–3)

- **Slice 00:** Umbrella app, dependencies, multitenancy foundation, Organization resource
- **Slice 01:** AshAuthentication, User resource, JWT with `organization_id` claim
- **Slice 02:** Project resource, ProjectMembership, AshJsonApi endpoints
- **Slice 03:** DailyLog create action, audio upload to Tigris (org-prefixed)
- **Slice 04:** Ash Reactor pipeline — Whisper, Claude, photo captioning
- **Slice 05:** Imprintor PDF generation, PDF stored to Tigris
- **Slice 06:** Phoenix Channels, org-namespaced PubSub, pipeline broadcasts
- **Slice 07:** Email (Swoosh), push notifications
- **Slice 08:** Procore integration (Enterprise)
- **Slice 09:** React Native app — all screens, dual audio, offline queue

### Phase 2 — Growth (Months 4–6)

- Self-hosted Whisper (`large-v3-turbo` via Rust NIF)
- Noise pre-processing (`dasp` Rust crate)
- PM web dashboard (LiveView, tenant-scoped)
- AshGraphQL for dashboard
- Autodesk Construction Cloud integration
- Slack / Teams notifications
- Ash Paper Trail audit views per tenant

### Phase 3 — Scale (Months 7–12)

- Multi-language beyond EN/ES
- Custom report templates per organization
- Analytics dashboard per tenant
- Weather API auto-populate
- Inspector sign-off workflow
- OSHA incident report auto-generation
- Mobile offline enhancements

---

_Version 1.1 — Multitenancy (attribute strategy, row-level) is foundational and implemented in Slice 00 before any domain resources. All Ash resources generated via `mix ash.gen.resource`. External API contracts subject to upstream versioning._
