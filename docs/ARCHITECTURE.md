# ARCHITECTURE.md

# SiteVoice AI — System Architecture

**Version:** 1.0
**Last Updated:** May 2025
**Audience:** Engineers, Claude Code agent
**Related:** `docs/APPLICATION_SPEC.md`, `docs/DOMAIN_MODEL.md`

This document describes the system architecture of SiteVoice AI — how the pieces fit together, why they were chosen, how data flows through the system, and what the boundaries are between components. Read this alongside the spec, not instead of it.

---

## Table of Contents

1. [Architectural Philosophy](#1-architectural-philosophy)
2. [System Context](#2-system-context)
3. [Component Overview](#3-component-overview)
4. [Mobile Architecture](#4-mobile-architecture)
5. [Backend Architecture](#5-backend-architecture)
6. [Ash Domain Architecture](#6-ash-domain-architecture)
7. [Multitenancy Architecture](#7-multitenancy-architecture)
8. [AI Pipeline Architecture](#8-ai-pipeline-architecture)
9. [Real-time Architecture](#9-real-time-architecture)
10. [Storage Architecture](#10-storage-architecture)
11. [Job Processing Architecture](#11-job-processing-architecture)
12. [Authentication & Authorization Flow](#12-authentication--authorization-flow)
13. [Data Flow Diagrams](#13-data-flow-diagrams)
14. [Process Boundary Map](#14-process-boundary-map)
15. [Deployment Architecture](#15-deployment-architecture)
16. [Key Design Decisions](#16-key-design-decisions)
17. [Future Architecture](#17-future-architecture)

---

## 1. Architectural Philosophy

SiteVoice AI is built around three principles:

**Declarative over imperative.** Business logic is expressed as Ash resource definitions, actions, policies, and Reactor steps — not as procedural controller code. The system's behaviour is readable from its declarations.

**Process boundaries are explicit.** Elixir's concurrency model means tenant context, authentication state, and configuration must be explicitly re-established at every process boundary (HTTP request, Channel message, Oban worker, Reactor async step). Nothing is implicit across process boundaries.

**Slices, not layers.** Features are built as vertical slices cutting through the full stack (mobile → API → domain → DB → storage). Each slice is independently deployable and testable. Dependencies between slices are one-directional.

---

## 2. System Context

```
                          ┌─────────────────────────────────┐
                          │        External Users            │
                          │  Foreman · PM · Org Admin        │
                          └──────────────┬──────────────────┘
                                         │
                              iOS / Android device
                                         │
                          ┌──────────────▼──────────────────┐
                          │       React Native App           │
                          │     (Expo, @rn-voice, expo-av)   │
                          └──────┬─────────────┬────────────┘
                                 │ HTTPS        │ WSS
                    REST/JSON:API │              │ Phoenix Channel
                                 │              │
                          ┌──────▼──────────────▼────────────┐
                          │    SiteVoice API                  │
                          │    Phoenix + Elixir               │
                          │    Fly.io (phx region)            │
                          └──┬────────┬──────────┬───────────┘
                             │        │           │
              ┌──────────────▼┐  ┌────▼──────┐  ┌▼──────────────────┐
              │  PostgreSQL   │  │  Tigris   │  │  External AI APIs  │
              │  (Fly.io)     │  │  Storage  │  │  OpenAI Whisper    │
              │  Oban + Data  │  │  Audio    │  │  Anthropic Claude  │
              └───────────────┘  │  Photos   │  └───────────────────┘
                                 │  PDFs     │
                                 └───────────┘

                          ┌──────────────────────────────────┐
                          │    External Integrations          │
                          │    Procore · Resend email         │
                          └──────────────────────────────────┘
```

### External Systems

| System               | Role                                  | Protocol              |
| -------------------- | ------------------------------------- | --------------------- |
| OpenAI Whisper API   | Audio transcription                   | HTTPS REST            |
| Anthropic Claude API | Report structuring + photo captioning | HTTPS REST            |
| Tigris               | File storage (audio, photos, PDFs)    | S3-compatible HTTPS   |
| Procore              | Daily log push (Enterprise)           | HTTPS REST            |
| Resend               | Transactional email delivery          | HTTPS REST via Swoosh |
| Fly.io               | Hosting, managed Postgres             | —                     |

---

## 3. Component Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         REACT NATIVE APP                            │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ┌──────────┐  │
│  │ @rn-voice    │  │  expo-av     │  │ API Client│  │  MMKV    │  │
│  │ Live STT     │  │ Audio Record │  │ JSON:API  │  │ Offline  │  │
│  │ (display)    │  │ (.m4a file)  │  │ + Phoenix │  │ Queue    │  │
│  └──────────────┘  └──────────────┘  │ Channel   │  └──────────┘  │
│                                       └───────────┘                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTPS / WSS + JWT
┌───────────────────────────────▼─────────────────────────────────────┐
│                      PHOENIX / ELIXIR BACKEND                       │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      Router / Plugs                          │   │
│  │   VerifyToken → SetTenant → AshJsonApi / Channels           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │  AshJsonApi  │  │   Phoenix    │  │    AshAuthentication      │  │
│  │  REST API    │  │   Channels   │  │    + Ash Policies         │  │
│  │  (JSON:API)  │  │   (WSS)      │  │    + Ash Paper Trail      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────────────┘  │
│         │                 │                                         │
│  ┌──────▼─────────────────▼───────────────────────────────────┐    │
│  │                    Ash Framework                             │    │
│  │                                                             │    │
│  │  SiteVoice.Accounts   │  SiteVoice.Projects                │    │
│  │  SiteVoice.Reporting  │  SiteVoice.Integrations            │    │
│  │  SiteVoice.Admin      │                                     │    │
│  │                                                             │    │
│  │  Multitenancy: attribute strategy (organization_id)        │    │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                   │
│  ┌──────────────────────────────▼──────────────────────────────┐   │
│  │                    Ash Reactor                               │   │
│  │                                                             │   │
│  │  ProcessRecording Reactor                                   │   │
│  │  SetTenant → FetchAudio → Whisper → Claude → PDF → Notify  │   │
│  └──────────────────────────────┬──────────────────────────────┘   │
│                                 │                                   │
│  ┌───────────────┐  ┌───────────▼──────────────────────────────┐   │
│  │  Oban         │  │  Phoenix.PubSub                          │   │
│  │  Job Queue    │  │  Topics: "org:{id}:log:{id}"             │   │
│  │  (5 queues)   │  │  (org-namespaced)                        │   │
│  └───────┬───────┘  └──────────────────────────────────────────┘   │
└──────────┼──────────────────────────────────────────────────────────┘
           │
     ┌─────▼──────────────────────────────────────────────────┐
     │                  Data Layer                             │
     │                                                        │
     │  PostgreSQL              Tigris (S3)                   │
     │  ├─ organizations        ├─ sitevoice-audio/           │
     │  ├─ users                │    {org_id}/{proj_id}/...   │
     │  ├─ projects             ├─ sitevoice-photos/          │
     │  ├─ daily_logs           │    {org_id}/{proj_id}/...   │
     │  ├─ photos               └─ sitevoice-pdfs/            │
     │  ├─ integrations              {org_id}/{proj_id}/...   │
     │  └─ oban_jobs                                          │
     └────────────────────────────────────────────────────────┘
```

---

## 4. Mobile Architecture

### 4.1 Structure

```
mobile/
├── src/
│   ├── screens/
│   │   ├── HomeScreen.tsx
│   │   ├── RecordingScreen.tsx
│   │   ├── ProcessingScreen.tsx
│   │   ├── ReviewScreen.tsx
│   │   └── SuccessScreen.tsx
│   ├── hooks/
│   │   ├── useRecording.ts       ← dual audio strategy
│   │   ├── useChannel.ts         ← Phoenix Channel client
│   │   ├── useOfflineQueue.ts    ← MMKV + BackgroundFetch
│   │   └── useAuth.ts            ← JWT storage + refresh
│   ├── api/
│   │   ├── client.ts             ← JSON:API base client
│   │   ├── dailyLogs.ts
│   │   └── projects.ts
│   ├── storage/
│   │   └── mmkv.ts               ← offline queue persistence
│   └── utils/
│       └── audio.ts
```

### 4.2 Dual Audio Strategy

The recording screen runs two audio systems simultaneously. They serve different purposes and must not be confused.

```
Foreman taps Record
        │
        ├──────────────────────────────────────┐
        ▼                                      ▼
@react-native-voice/voice               expo-av Audio.Recording
(Android: Google SpeechRecognizer)      HIGH_QUALITY preset
(iOS: Apple Speech.framework)           records .m4a to device
        │                                      │
        ▼                                      │
Live partial results → UI display             │
(word-by-word, instant, free)                 │
                                              │
Foreman taps Stop                             │
        │                                     │
        ▼                                     ▼
Voice.stop()                    recording.stopAndUnloadAsync()
(display freezes — UI only)     audio file ready at URI
                                              │
                                             UPLOAD to Phoenix API
                                             (this file goes to Whisper)
```

**Why two systems:** On-device STT gives zero-latency visual feedback — the foreman sees words appearing in real time, which builds confidence. But on-device models are weak on construction jargon and noisy audio. The `.m4a` file sent to OpenAI Whisper produces the authoritative transcript that feeds Claude. The on-device transcript is display-only and discarded after processing.

### 4.3 Offline Queue Architecture

```
Network available?
        │
       YES ──────────────────────► Upload directly to API
        │
       NO
        │
        ▼
Save audio to expo-file-system
Store metadata to MMKV:
  { logId, audioUri, token, queuedAt }
        │
        ▼
BackgroundFetch task registered
  polls every 15 minutes
        │
  Connectivity detected
        │
        ▼
Process MMKV queue in order:
  for each item:
    upload audio (JWT in item.token restores org context server-side)
    on success → remove from MMKV queue
    on failure → leave in queue, retry next poll
```

**Key point:** The JWT stored with each offline queue item carries `organization_id`. When the item is eventually uploaded, the server's `SetTenant` plug extracts it from the JWT automatically. No special offline handling needed on the server.

### 4.4 Phoenix Channel Client

```
Socket connected with JWT token param
        │
        ▼
channel = socket.channel("recording:{log_id}")
channel.join()
        │
        ├── Push: "recording_complete" → triggers Oban job server-side
        │
        ├── Receive: "processing_started"  → show Processing screen
        ├── Receive: "pipeline_update"     → update step progress UI
        ├── Receive: "report_ready"        → navigate to Review screen
        └── Receive: "pipeline_failed"     → show error + retry option
```

---

## 5. Backend Architecture

### 5.1 Phoenix Application Structure

```
apps/
├── site_voice/                        ← Core business logic
│   └── lib/site_voice/
│       ├── accounts/
│       │   ├── accounts.ex            ← Ash Domain
│       │   └── resources/
│       │       ├── organization.ex
│       │       ├── user.ex
│       │       └── token.ex
│       ├── projects/
│       │   ├── projects.ex
│       │   └── resources/
│       │       ├── project.ex
│       │       └── project_membership.ex
│       ├── reporting/
│       │   ├── reporting.ex
│       │   ├── resources/
│       │   │   ├── daily_log.ex
│       │   │   └── photo.ex
│       │   ├── reactors/
│       │   │   └── process_recording.ex
│       │   ├── steps/
│       │   │   ├── set_tenant.ex
│       │   │   ├── fetch_log.ex
│       │   │   ├── fetch_from_tigris.ex
│       │   │   ├── transcribe_whisper.ex
│       │   │   ├── structure_with_claude.ex
│       │   │   ├── caption_photos.ex
│       │   │   ├── generate_pdf.ex
│       │   │   ├── store_tigris.ex
│       │   │   └── broadcast_ready.ex
│       │   └── workers/
│       │       └── audio_processor.ex
│       ├── integrations/
│       │   ├── integrations.ex
│       │   ├── resources/
│       │   │   ├── integration.ex
│       │   │   └── integration_event.ex
│       │   └── adapters/
│       │       └── procore.ex
│       ├── admin/
│       │   └── admin.ex               ← No multitenancy
│       └── storage.ex                 ← Tigris wrapper
│
└── site_voice_web/                    ← HTTP + WebSocket layer
    └── lib/site_voice_web/
        ├── router.ex
        ├── plugs/
        │   ├── verify_token.ex
        │   └── set_tenant.ex
        ├── channels/
        │   ├── user_socket.ex
        │   ├── recording_channel.ex
        │   └── log_channel.ex
        └── endpoint.ex
```

### 5.2 Request Lifecycle

```
HTTP Request arrives
        │
        ▼
Endpoint (SSL termination, Cowboy)
        │
        ▼
Router — matches path to pipeline
        │
        ▼
:api pipeline:
  plug :accepts, ["json"]
  plug VerifyToken          ← validates JWT, sets conn.assigns.current_user
  plug SetTenant            ← calls Ash.Query.set_tenant(current_user.organization_id)
        │
        ▼
AshJsonApi router
  matches resource + action
        │
        ▼
Ash action executes
  ├─ multitenancy filter applied automatically (WHERE organization_id = ?)
  ├─ Ash Policy checked (actor-based authorization)
  ├─ Changeset validated
  └─ Data layer query executed
        │
        ▼
JSON:API response serialized
        │
        ▼
Response → client
```

### 5.3 Plug Pipeline

```
┌────────────────────────────────────────────────────┐
│ Pipeline: :api                                     │
│                                                    │
│  1. plug :accepts, ["json"]                        │
│     → rejects non-JSON requests                    │
│                                                    │
│  2. plug VerifyToken                               │
│     → validates Bearer JWT                         │
│     → decodes claims (sub, organization_id, role)  │
│     → assigns current_user to conn                 │
│     → 401 if invalid/expired                       │
│                                                    │
│  3. plug SetTenant                                 │
│     → reads current_user.organization_id           │
│     → calls Ash.Query.set_tenant(org_id)                 │
│     → all Ash queries in this process now scoped   │
│                                                    │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ Pipeline: :admin (platform admins only)            │
│                                                    │
│  1. plug :accepts, ["json"]                        │
│  2. plug VerifyAdminToken                          │
│     → validates platform admin JWT                 │
│     → NO SetTenant call — cross-tenant access      │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## 6. Ash Domain Architecture

### 6.1 Domain Map

```
┌─────────────────────────────────────────────────────────────────┐
│  SiteVoice.Accounts                                             │
│  ┌────────────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Organization       │  │ User         │  │ Token          │  │
│  │ (global — tenant   │  │ (tenanted)   │  │ (global)       │  │
│  │  root, no org_id)  │  │              │  │                │  │
│  └────────────────────┘  └──────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  SiteVoice.Projects                                             │
│  ┌──────────────────────────┐  ┌────────────────────────────┐  │
│  │ Project (tenanted)       │  │ ProjectMembership          │  │
│  │                          │  │ (tenanted)                 │  │
│  └──────────────────────────┘  └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  SiteVoice.Reporting                          ← core domain     │
│  ┌──────────────────────────┐  ┌────────────────────────────┐  │
│  │ DailyLog (tenanted)      │  │ Photo (tenanted)           │  │
│  │ actions:                 │  │                            │  │
│  │  :submit_recording       │  │                            │  │
│  │  :apply_transcript       │  │                            │  │
│  │  :apply_structure        │  │                            │  │
│  │  :approve_and_submit     │  │                            │  │
│  │  :mark_failed            │  │                            │  │
│  └──────────────────────────┘  └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  SiteVoice.Integrations                                         │
│  ┌──────────────────────────┐  ┌────────────────────────────┐  │
│  │ Integration (tenanted)   │  │ IntegrationEvent           │  │
│  │                          │  │ (tenanted)                 │  │
│  └──────────────────────────┘  └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  SiteVoice.Admin                    ← platform admin only       │
│  No multitenancy — cross-tenant visibility                      │
│  Never exposed via public AshJsonApi router                     │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Resource Layer Architecture

Each Ash resource is composed of these layers, evaluated in order:

```
Incoming action call (e.g. DailyLog.submit_recording)
        │
        ▼
┌─────────────────────────────────────────────┐
│ 1. Multitenancy                             │
│    AshPostgres appends:                     │
│    WHERE organization_id = $tenant          │
│    (happens before any policy check)        │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ 2. Ash Policy                               │
│    actor-based rules evaluated              │
│    (role checks, relationship checks)       │
│    → :authorized or :forbidden              │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ 3. Changeset / Validation                   │
│    attribute validation                     │
│    relationship management                  │
│    custom Changes applied                   │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ 4. Data Layer (AshPostgres)                 │
│    SQL query with tenant filter             │
│    transaction if needed                    │
│    after_action hooks fire                  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ 5. Paper Trail                              │
│    change recorded with actor + timestamp   │
└─────────────────────────────────────────────┘
```

### 6.3 DailyLog State Machine

```
                    :submit_recording (create)
                              │
                              ▼
                         [ :pending ]
                              │
                    Oban job enqueued
                    Reactor starts
                              │
                    :apply_transcript
                              │
                              ▼
                        [ :processing ]
                              │
                    :apply_structure
                              │
                              ▼
                          [ :draft ]  ◄──── Foreman reviews
                              │
               ┌──────────────┴──────────────┐
               │                             │
          approve                        failure at
          and_submit                     any Reactor step
               │                             │
               ▼                             ▼
          [ :submitted ]               [ :failed ]
          (terminal)                   (retriable via Oban)
```

---

## 7. Multitenancy Architecture

### 7.1 Tenant Propagation Map

Every arrow represents a process boundary where tenant context must be explicitly re-established.

```
                    JWT issued at login
                    contains organization_id claim
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    HTTP Request    WebSocket conn    Offline upload
          │                │                │
    VerifyToken       VerifyToken      VerifyToken
    SetTenant plug    in socket        (on reconnect)
    Ash.Query.set_tenant()  assigns          Ash.Query.set_tenant()
          │                │
          │          Channel join
          │          Ash.Query.set_tenant()
          │                │
          │          Channel handle_in
          │          Ash.Query.set_tenant()  ← re-apply each time
          │
    Ash action ── organization_id in job args
          │               │
    Changeset       Oban Worker
    after_action    perform/1
    enqueues job    Ash.Query.set_tenant()  ← first line, always
                          │
                    Reactor starts
                          │
                    SetTenant step
                    Ash.Query.set_tenant()
                    wait_for on all
                    subsequent steps
                          │
                    ┌─────┴──────┐
                    ▼            ▼
               structure    caption_photos
               (async)      (async)
               Both inherit tenant from
               SetTenant step in same process
```

### 7.2 Data Isolation Model

```
┌─────────────────────────────────────────────────────┐
│                  PostgreSQL                          │
│                                                     │
│  organizations table (global)                       │
│  ┌─────────────────────────────────────────────┐   │
│  │ id: org-abc  │ name: Turner West             │   │
│  │ id: org-xyz  │ name: Skanska Pacific         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  daily_logs table (tenanted)                        │
│  ┌───────────────────────────────────────────────┐  │
│  │ id  │ organization_id │ date  │ status │ ...  │  │
│  │ 001 │ org-abc         │ 05-14 │ draft  │ ...  │  │
│  │ 002 │ org-abc         │ 05-13 │ submit │ ...  │  │
│  │ 003 │ org-xyz         │ 05-14 │ draft  │ ...  │  │ ← invisible to org-abc
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Query with Ash.Query.set_tenant("org-abc"):              │
│  SELECT * FROM daily_logs                           │
│  WHERE organization_id = 'org-abc'    ← auto-added  │
│  AND   ...your filters...                           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                    Tigris Storage                    │
│                                                     │
│  sitevoice-audio/                                   │
│  ├── org-abc/proj-1/2025-05-14/log-001.m4a          │
│  ├── org-abc/proj-1/2025-05-13/log-002.m4a          │
│  └── org-xyz/proj-9/2025-05-14/log-003.m4a          │
│                          ↑                           │
│                 org-xyz prefix = logical isolation   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                  Phoenix.PubSub                      │
│                                                     │
│  "org:org-abc:log:001"  ← only org-abc subscribes  │
│  "org:org-xyz:log:003"  ← only org-xyz subscribes  │
│                                                     │
│  Cross-subscription impossible by convention        │
└─────────────────────────────────────────────────────┘
```

---

## 8. AI Pipeline Architecture

### 8.1 Reactor Step Graph

```
                    input: log_id
                    input: organization_id
                           │
                           ▼
                    ┌─────────────┐
                    │  set_tenant │  ← Ash.Query.set_tenant(organization_id)
                    └──────┬──────┘
                           │ wait_for (all Ash steps depend on this)
                           ▼
                    ┌─────────────┐
                    │  fetch_log  │  ← Ash read DailyLog
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │  fetch_audio    │  ← GET from Tigris
                    └──────┬──────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │  transcribe     │  ← POST OpenAI Whisper API
                    │  (Whisper)      │    returns: transcript string
                    └──────┬──────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │ save_transcript │  ← Ash update DailyLog
                    │ (Ash update)    │    status → :processing
                    └──────┬──────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼  async: true            ▼  async: true
    ┌─────────────────┐      ┌─────────────────────┐
    │   structure     │      │   caption_photos     │
    │   (Claude API)  │      │   (Claude Vision)    │
    │   → 6 category  │      │   → captions +       │
    │     JSON        │      │     categories       │
    └────────┬────────┘      └──────────┬───────────┘
              │                         │
              └────────────┬────────────┘
                           │ (both must complete)
                           ▼
                    ┌─────────────────┐
                    │ save_structure  │  ← Ash update DailyLog
                    │ (Ash update)    │    status → :draft
                    └──────┬──────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │  generate_pdf   │  ← Imprintor (Typst → binary)
                    └──────┬──────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │  store_pdf      │  ← PUT to Tigris
                    │                 │    key: {org_id}/...
                    └──────┬──────────┘
                           │
                           ▼
                    ┌─────────────────┐
                    │  notify         │  ← PubSub broadcast
                    │                 │    "org:{org_id}:log:{id}"
                    └─────────────────┘
```

### 8.2 Concurrency Model

Steps 4 (`structure`) and 5 (`caption_photos`) run concurrently. Reactor detects this from the dependency graph — neither depends on the other's output. Wall-clock time savings:

```
Sequential (without async):
  Whisper(~5s) → Claude structure(~8s) → Claude vision(~6s) → PDF(~3s)
  Total: ~22s

Concurrent (with async):
  Whisper(~5s) → Claude structure(~8s) ─┐
                                         ├─ max(8,6) = 8s → PDF(~3s)
                 Claude vision(~6s)   ───┘
  Total: ~16s
```

### 8.3 Error Handling & Compensation

```
Any step fails
        │
        ▼
Reactor calls compensate() on completed steps in reverse order
        │
        ▼
save_transcript.compensate():
  → Ash update DailyLog: status = :pending
        │
        ▼
Oban marks job as failed
        │
        ▼
Oban retries (max_attempts: 3, exponential backoff)
        │
  After 3 failures:
        │
        ▼
Oban marks job :exhausted
DailyLog remains :failed
Sentry error captured
        │
        ▼
PubSub broadcast: "pipeline_failed"
→ client shows retry option
```

### 8.4 Claude Structuring — Prompt Architecture

```
System prompt (stable — defines output schema):
  "Return ONLY JSON with keys: labor, progress, equipment,
   materials, delays, safety, accuracy_score..."

User message (dynamic — the transcript):
  "North wall framing 80% complete. Martinez crew, 6 guys..."

Response (structured JSON):
  {
    "labor":     [...],
    "progress":  [...],
    "equipment": [...],
    "materials": [...],
    "delays":    [...],
    "safety":    [...],
    "accuracy_score": 0.96
  }

Parsed → atomized keys → saved to DailyLog JSONB columns
```

---

## 9. Real-time Architecture

### 9.1 Channel Topology

```
Phoenix Socket (authenticated via JWT token param)
        │
        ├── "recording:{log_id}"   ← RecordingChannel
        │   join:     verify log belongs to user's org
        │   handle_in:
        │     "recording_complete" → enqueue Oban job
        │   handle_out:
        │     "processing_started" → client shows Processing screen
        │
        └── "log:{log_id}"         ← LogChannel
            join:     verify read access (foreman or PM in same org)
            subscribed to PubSub topic: "org:{org_id}:log:{log_id}"
            handle_info:
              {:pipeline_update, step, status} → push to client
              {:report_ready, pdf_url}         → push to client
              {:pipeline_failed, reason}       → push to client
```

### 9.2 PubSub Message Flow

```
Reactor step completes
        │
        ▼
Phoenix.PubSub.broadcast(
  SiteVoice.PubSub,
  "org:#{org_id}:log:#{log_id}",    ← tenanted topic
  {:pipeline_update, %{step: :transcribed, status: :complete}}
)
        │
        ▼
LogChannel receives in handle_info
        │
        ▼
push(socket, "pipeline_update", %{step: "transcribed", status: "complete"})
        │
        ▼
React Native client receives event
Updates ProcessingScreen step list
```

### 9.3 Tenant Isolation in PubSub

```
Topic format: "org:{org_id}:{resource}:{id}"

org-abc foreman's socket joins: "org:org-abc:log:001"
org-xyz foreman's socket joins: "org:org-xyz:log:003"

Broadcast to "org:org-abc:log:001"
→ only org-abc subscribers receive it
→ org-xyz never sees org-abc events

This is enforced by convention, not by Phoenix itself.
The convention is enforced by:
  1. Channel join verification (checks log belongs to user's org)
  2. All broadcasts use org-prefixed topic strings
  3. No bare "log:{id}" topics ever used (code review rule)
```

---

## 10. Storage Architecture

### 10.1 Bucket Strategy

Three buckets, single tenant account, org-prefixed keys:

```
sitevoice-audio/
  Purpose: raw .m4a recordings
  Lifecycle: delete after successful transcription (configurable per org)
  Encryption: AES-256 server-side
  Access: private (presigned URLs only)

sitevoice-photos/
  Purpose: site photos attached to daily logs
  Lifecycle: 7 years (construction documentation standard)
  Encryption: AES-256 server-side
  Access: private (presigned URLs, 1-hour expiry)

sitevoice-pdfs/
  Purpose: generated daily log PDFs (PDF/A-3a)
  Lifecycle: 7 years (legal requirement)
  Encryption: AES-256 server-side
  Access: private (presigned URLs, 1-hour expiry)
```

### 10.2 Key Naming Convention

```
{bucket}/{organization_id}/{project_id}/{...}/{filename}

Audio:
  sitevoice-audio/{org_id}/{proj_id}/{date}/{log_id}.m4a
  Example: sitevoice-audio/org-abc/proj-1/2025-05-14/log-001.m4a

Photos:
  sitevoice-photos/{org_id}/{proj_id}/{log_id}/{photo_id}.jpg
  Example: sitevoice-photos/org-abc/proj-1/log-001/photo-007.jpg

PDFs:
  sitevoice-pdfs/{org_id}/{proj_id}/{year}/{month}/{log_id}.pdf
  Example: sitevoice-pdfs/org-abc/proj-1/2025/05/log-001.pdf
```

`organization_id` as the first path segment provides logical tenant isolation within shared buckets. A tenant's data can be enumerated, exported, or deleted by prefix without touching other tenants.

### 10.3 Access Pattern

```
Upload (audio/photo):
  Client → Phoenix API (multipart/form-data)
  Phoenix → validates auth + tenant
  Phoenix → SiteVoice.Storage.store_audio(key, binary)
  → ExAws.S3.put_object(bucket, key, binary)
  → Tigris stores with AES-256

Download (PDF delivery):
  Phoenix generates presigned URL (1hr expiry)
  URL sent to client / email
  Client fetches directly from Tigris CDN
  No Phoenix proxy — Tigris global CDN serves directly

Internal (Reactor step):
  Reactor → SiteVoice.Storage.fetch(key)
  → ExAws.S3.get_object(bucket, key)
  → binary returned in-memory to Reactor step
```

---

## 11. Job Processing Architecture

### 11.1 Oban Queue Map

```
┌─────────────────────────────────────────────────────────────┐
│                       Oban                                  │
│                  (Postgres-backed)                          │
│                                                             │
│  Queue: audio (concurrency: 10)                             │
│  └─ AudioProcessor             triggered by: DailyLog       │
│                                 :submit_recording action    │
│                                                             │
│  Queue: ai (concurrency: 5)                                 │
│  └─ (future: dedicated AI jobs if pipeline grows)           │
│                                                             │
│  Queue: pdf (concurrency: 5)                                │
│  └─ (future: dedicated PDF jobs if decoupled)               │
│                                                             │
│  Queue: integrations (concurrency: 10)                      │
│  └─ ProcoreDispatcher          triggered by: :submitted     │
│  └─ EmailDispatcher            triggered by: :submitted     │
│                                                             │
│  Queue: notifications (concurrency: 20)                     │
│  └─ DailyReminderWorker        cron: 06:00 daily            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 11.2 Worker Lifecycle

```
DailyLog :submit_recording action fires
        │
        ▼
after_action Change: EnqueueProcessing
  %{log_id: log.id, organization_id: log.organization_id}
  |> AudioProcessor.new()
  |> Oban.insert()
        │
        ▼
Oban persists job to oban_jobs table (PostgreSQL)
        │
        ▼
Oban worker picks up job (queue: :audio, concurrency 10)
        │
        ▼
AudioProcessor.perform(%Job{args: %{log_id, organization_id}})
  Ash.Query.set_tenant(org_id)         ← tenant established
  ProcessRecording Reactor.run() ← full pipeline
        │
        ▼
Success → Oban marks :completed
Failure → Oban retries (max 3, exponential backoff)
Exhausted → Oban marks :discarded, Sentry alert
```

### 11.3 Tenant in Jobs

```
WRONG — loses tenant context:
  %{log_id: log.id}
  |> AudioProcessor.new()

CORRECT — always include organization_id:
  %{log_id: log.id, organization_id: log.organization_id}
  |> AudioProcessor.new()

WRONG — forgetting to set tenant in worker:
  def perform(%Job{args: %{"log_id" => id}}) do
    ProcessRecording.run(%{log_id: id})  # no tenant set!

CORRECT — first line always:
  def perform(%Job{args: %{"log_id" => id, "organization_id" => org_id}}) do
    Ash.Query.set_tenant(org_id)              # always first
    ProcessRecording.run(%{log_id: id, organization_id: org_id})
```

---

## 12. Authentication & Authorization Flow

### 12.1 Registration Flow

```
POST /organizations
  body: { org_name, email, password, name }
        │
        ▼
RegisterOrganization action (no tenant context — creates the tenant)
  Transaction:
    1. Ash.create(Organization, %{name, slug, tier: :pro})
    2. Ash.create(User, %{organization_id: org.id, role: :org_admin, ...})
        │
        ▼
AshAuthentication issues JWT:
  { sub: user.id, organization_id: org.id, role: :org_admin }
        │
        ▼
Client stores JWT
All subsequent requests carry this JWT → SetTenant plug activates
```

### 12.2 Login Flow

```
POST /auth/sign-in
  body: { email, password }
        │
        ▼
AshAuthentication password strategy
  1. Finds user by email (global lookup — no tenant yet)
  2. Verifies bcrypt hash
  3. Issues JWT with organization_id claim
        │
        ▼
Client stores JWT
```

### 12.3 Authorization Layers

```
Request arrives for: GET /daily-logs
        │
Layer 1: Authentication
  VerifyToken plug validates JWT
  → 401 if invalid
        │
Layer 2: Tenant Isolation (automatic)
  SetTenant plug calls Ash.Query.set_tenant(org_id)
  AshPostgres adds WHERE organization_id = 'org-abc'
  → physically impossible to see another org's data
        │
Layer 3: Ash Policy (user-level)
  Actor role checked against action policy
  For :read on DailyLog:
    authorize_if actor_attribute_equals(:role, :pm)
    authorize_if actor_attribute_equals(:role, :org_admin)
    authorize_if relates_to_actor_via(:foreman)
  → 403 if none match
        │
Layer 4: Data returned
  Only records matching both tenant filter AND policy
```

---

## 13. Data Flow Diagrams

### 13.1 Happy Path — Foreman Submits Report

```
4:00 PM  Foreman opens app
         ├── GET /daily-logs?filter[date]=today  → status: pending
         └── GET /projects/me                   → project context

4:01 PM  Foreman taps Record
         ├── @rn-voice starts        → live transcript on screen
         └── expo-av starts recording → .m4a accumulating

4:02:30  Foreman taps Stop
         ├── @rn-voice stops (display freezes)
         ├── expo-av stops → .m4a ready
         ├── POST /daily-logs        → DailyLog created, status: :pending
         │     body: { date, audio_key, audio_duration }
         │     response: { id: log-001, status: pending }
         ├── PUT to Tigris           → audio binary uploaded
         │     key: org-abc/proj-1/2025-05-14/log-001.m4a
         └── Channel join "recording:log-001"

4:02:31  Server: Oban job enqueued
         Channel push: "processing_started"
         Client: shows Processing screen

4:02:31  Oban worker starts
         Ash.Query.set_tenant("org-abc")
         Reactor starts:

4:02:33  [Step 1] Fetch audio from Tigris
4:02:38  [Step 2] Whisper API → transcript (5s)
4:02:38  [Step 3] Ash save transcript, status → :processing
         PubSub: "pipeline_update" {step: transcribed}

4:02:38  [Step 4+5 concurrent]
4:02:46  Claude structure (8s) + Claude vision (6s) → both done
         [Step 6] Ash save structure, status → :draft
         PubSub: "pipeline_update" {step: structured}

4:02:49  [Step 7] Imprintor → PDF binary (3s)
4:02:49  [Step 8] PUT PDF to Tigris
         [Step 9] PubSub broadcast: "report_ready"
         Channel push: "report_ready" { pdf_url }

4:02:49  Client: navigates to Review screen
         Foreman sees 6 category cards, accuracy: 96%

4:03:10  Foreman reads draft, makes 1 edit to equipment section
         PATCH /daily-logs/log-001 → saves edit

4:03:15  Foreman taps Submit
         PATCH /daily-logs/log-001 action: :approve_and_submit
         → status: :submitted
         → Oban enqueues: EmailDispatcher, ProcoreDispatcher

4:03:16  PM receives PDF via email
         Procore daily log created

Total foreman time: ~75 seconds
Total system time from stop to report ready: ~18 seconds
```

### 13.2 Offline Flow

```
Foreman is in basement — no signal
        │
        ▼
Foreman taps Record → speaks → taps Stop
        │
        ▼
expo-av saves .m4a to device filesystem
MMKV stores: { logId, audioUri, token, queuedAt }
UI shows: "Saved offline — will sync when connected"
        │
        (time passes)
        │
Foreman walks outside — signal returns
        │
        ▼
BackgroundFetch task fires (or app foregrounds)
Reads MMKV queue
        │
        ▼
For each queued item:
  POST /daily-logs (JWT in item.token → org context restored)
  PUT audio to Tigris
  Channel join
  → normal pipeline from this point
        │
        ▼
Item removed from MMKV queue
```

---

## 14. Process Boundary Map

Every horizontal line below is a process boundary. Tenant context does NOT cross these boundaries automatically.

```
┌────────────────────────────────────────────────────────────┐
│  HTTP Request Process                                      │
│  Ash.Query.set_tenant() called by SetTenant plug                 │
│  All Ash calls in this process are tenant-scoped          │
└────────────────────────────┬───────────────────────────────┘
                             │ Oban.insert() — job args cross boundary
════════════════════════════════ PROCESS BOUNDARY ═══════════
┌────────────────────────────▼───────────────────────────────┐
│  Oban Worker Process                                       │
│  perform/1 must call Ash.Query.set_tenant(args["organization_id"])│
│  first line — no exceptions                               │
└────────────────────────────┬───────────────────────────────┘
                             │ Reactor.run() called
═══════════════════════════════ PROCESS BOUNDARY ════════════
┌────────────────────────────▼───────────────────────────────┐
│  Ash Reactor Process                                       │
│  SetTenant step runs first (wait_for on all Ash steps)    │
│  Ash calls in sequential steps: scoped                    │
└────────────────────────────┬───────────────────────────────┘
                             │ async?: true spawns tasks
═══════════════════════════════ PROCESS BOUNDARY ════════════
┌────────────────────────────▼───────────────────────────────┐
│  Reactor Async Step Process (structure, caption_photos)    │
│  Ash.Query.set_tenant() inherited from Reactor SetTenant step   │
│  (same session — Reactor manages this)                    │
└────────────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════════
┌────────────────────────────────────────────────────────────┐
│  Phoenix Channel Process (long-lived)                      │
│  Ash.Query.set_tenant() called on join                          │
│  Re-called on every handle_in                             │
│  org_id stored in socket.assigns.organization_id          │
└────────────────────────────────────────────────────────────┘

════════════════════════════════════════════════════════════
┌────────────────────────────────────────────────────────────┐
│  Task.async (if used anywhere)                             │
│  Must receive org_id as argument                          │
│  Must call Ash.Query.set_tenant(org_id) inside the task         │
└────────────────────────────────────────────────────────────┘
```

---

## 15. Deployment Architecture

### 15.1 Fly.io Topology

```
                     Internet
                         │
                    Fly.io Anycast
                         │
              ┌──────────▼──────────┐
              │   Fly.io Edge        │
              │   TLS termination    │
              │   HTTP/2             │
              └──────────┬──────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Phoenix │    │ Phoenix │    │ Phoenix │
    │ VM phx  │    │ VM phx  │    │ VM dfw  │
    │ (2 CPU) │    │ replica │    │ (future)│
    └────┬────┘    └────┬────┘    └─────────┘
         │              │
         └──────┬───────┘
                │
         ┌──────▼──────────┐
         │  Fly.io Postgres │
         │  primary: phx    │
         │  replica: ...    │
         └─────────────────┘
```

### 15.2 Runtime Configuration

```
config/runtime.exs reads all secrets from environment:
  DATABASE_URL
  AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  OPENAI_API_KEY
  ANTHROPIC_API_KEY
  TOKEN_SIGNING_SECRET
  SECRET_KEY_BASE
  PHX_HOST
  RESEND_API_KEY

Fly.io secrets store provides these at runtime.
Never in source code. Never in config/prod.exs.
```

### 15.3 Oban in Multi-Node Deployment

Oban uses PostgreSQL advisory locks for job coordination. Multiple Phoenix VMs share the same Postgres database — Oban ensures each job is picked up by exactly one worker across the cluster. No additional coordination layer needed.

---

## 16. Key Design Decisions

### Why Ash Framework over plain Ecto + Phoenix

Ash provides the structure that prevents architectural drift as the codebase grows. Without it, authorization logic leaks into controllers, business rules scatter across contexts, and API serialization becomes bespoke. Ash enforces a single location for each concern: resources for data + actions, policies for authorization, AshJsonApi for serialization. Every piece of code has a correct place to live.

### Why Ash Reactor over plain Oban workers

The audio processing pipeline has dependencies (transcript must exist before structuring), concurrent steps (structure and caption can run in parallel), and compensation requirements (reset status on failure). Encoding this in Oban workers requires imperative, hand-written orchestration logic. Reactor expresses it as a dependency graph — the concurrency and compensation are structural, not written.

### Why attribute multitenancy over schema-per-tenant

Schema-per-tenant requires a per-tenant migration runner, complicates admin cross-tenant queries, and adds significant ops overhead. For a construction SaaS at MVP scale with tens to hundreds of tenants, row-level isolation is operationally simpler and equally safe when implemented correctly via Ash. The `organization_id` leading all indexes ensures query performance doesn't degrade as tenant count grows.

### Why Tigris over S3 directly

Tigris provides S3-compatible APIs with a global CDN layer. Audio files uploaded from Phoenix AZ construction sites are stored close to origin. PDFs served to PMs in New York are pulled from a nearby edge node. This matters for a product where perceived speed (report delivery time) is a core metric, without requiring CloudFront or manual replication configuration.

### Why Imprintor over Gotenberg

Gotenberg requires running a separate Docker container (headless Chromium). Imprintor compiles Typst to PDF via a native Rust NIF — it runs in-process, returns a binary, requires no container orchestration. The Typst DSL produces cleaner, more maintainable templates than HTML/CSS for structured documents. PDF/A-3a standard is directly supported.

### Why OpenAI Whisper API (hosted) for MVP

Accuracy on noisy construction audio at the `large-v3` model level, zero infrastructure to manage, and `$0.006/min` cost is negligible at MVP scale. The migration path to self-hosted `whisper-rs` (Rust NIF) is isolated to a single Reactor step. When the trigger fires (first Enterprise client or cost > $500/month), nothing else changes.

---

## 17. Future Architecture

### Phase 2 — Self-Hosted Whisper

```
Current (MVP):
  TranscribeWhisper step → HTTP → OpenAI API

Future (Phase 2):
  TranscribeWhisper step → Rust NIF → whisper-rs (in-process)

Change scope: one Reactor step file
Everything else: unchanged
```

The NIF uses `DirtyCpu` scheduling to avoid blocking the BEAM scheduler during CPU-intensive inference:

```rust
#[rustler::nif(schedule = "DirtyCpu")]
fn transcribe(audio_data: Binary) -> NifResult<String> {
    let cleaned = preprocess_audio(&audio_data)?;   // dasp noise filter
    let transcript = run_whisper(&cleaned)?;         // whisper-rs large-v3-turbo
    Ok(transcript)
}
```

### Phase 2 — AshGraphQL for PM Dashboard

AshJsonApi (mobile) and AshGraphQL (dashboard) coexist in Ash with no conflict. Both read the same resource definitions. Both respect multitenancy. The dashboard addition requires no changes to existing resources — only adding GraphQL route declarations.

### Phase 3 — Schema-Per-Tenant (if required)

If an Enterprise client contractually requires schema isolation:

1. Ash context strategy (`strategy :context`) replaces `strategy :attribute`
2. `organization_id` column removed from tenanted tables
3. A per-tenant migration runner must be built
4. Oban, Channel, and Reactor tenant propagation changes from `Ash.Query.set_tenant(org_id)` to `Ash.Query.set_tenant(schema_name)`

This is a significant migration. The attribute strategy is chosen specifically to defer this cost until there is a contractual forcing function.

### Phase 3 — Analytics Domain

```
SiteVoice.Analytics (new domain)
  └─ DailyLogSummary (materialized view per tenant)
  └─ ProjectMetrics  (aggregated, tenant-scoped)
  └─ OrgDashboard    (rollup, tenant-scoped)

Populated by: Oban cron jobs reading from Reporting domain
Served by: AshGraphQL (PM/Owner dashboard)
```

---

_This document describes the architecture as of May 2025 (v1.0). It should be updated when significant structural decisions change. The APPLICATION_SPEC.md remains the source of truth for feature requirements; this document explains how the implementation fulfills them._
