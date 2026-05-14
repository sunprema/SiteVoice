# DOMAIN_MODEL.md
# SiteVoice AI — Ash Domain Model

**Version:** 1.0
**Last Updated:** May 2025
**Audience:** Engineers, Claude Code agent
**Related:** `docs/APPLICATION_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/CODING_STANDARDS.md`

This document is the authoritative reference for all Ash resource definitions, relationships, actions, policies, changes, and calculations. Use it when generating resources, writing tests, or understanding how domains relate to each other.

---

## Table of Contents

1. [Domain Overview](#1-domain-overview)
2. [Relationship Map](#2-relationship-map)
3. [SiteVoice.Accounts](#3-sitevoiceaccounts)
   - Organization
   - User
   - Token
4. [SiteVoice.Projects](#4-sitevoiceprojects)
   - Project
   - ProjectMembership
5. [SiteVoice.Reporting](#5-sitevoicereporting)
   - DailyLog
   - Photo
6. [SiteVoice.Integrations](#6-sitevoiceintegrations)
   - Integration
   - IntegrationEvent
7. [SiteVoice.Admin](#7-sitevoiceadmin)
8. [Changes Reference](#8-changes-reference)
9. [Calculations Reference](#9-calculations-reference)
10. [JSONB Field Schemas](#10-jsonb-field-schemas)
11. [Policy Matrix](#11-policy-matrix)
12. [AshJsonApi Route Map](#12-ashjsonapi-route-map)

---

## 1. Domain Overview

SiteVoice AI is organized into five Ash domains. Each domain owns a cohesive set of resources and exposes a clean API boundary. Domains never reach into each other's data layers directly.

```
┌─────────────────────────────────────────────────────┐
│  SiteVoice.Accounts                                 │
│  Organization (global) · User (tenanted)            │
│  Token (global)                                     │
│  → Authentication, identity, tenant root            │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  SiteVoice.Projects                                 │
│  Project (tenanted) · ProjectMembership (tenanted)  │
│  → Sites, teams, project configuration              │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  SiteVoice.Reporting                  ← core domain │
│  DailyLog (tenanted) · Photo (tenanted)             │
│  → Voice memos, AI pipeline, reports, PDFs          │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  SiteVoice.Integrations                             │
│  Integration (tenanted) · IntegrationEvent (tenanted│
│  → Procore, ACC, Slack, email push adapters         │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  SiteVoice.Admin                                    │
│  Cross-tenant read access — platform admins only    │
│  Never exposed via public AshJsonApi router         │
└─────────────────────────────────────────────────────┘
```

### Multitenancy Rule

All resources except `Organization` and `Token` are tenanted:

```elixir
# Every tenanted resource must include this block
multitenancy do
  strategy  :attribute
  attribute :organization_id
end
```

`organization_id` is:
- Always `allow_nil?: false`
- Always `public?: false` (never serialized in API responses)
- Never accepted from client request bodies — sourced from JWT only
- Always the **leading column** on all Postgres indexes

---

## 2. Relationship Map

```
Organization (global — tenant root)
│
├── has_many ──► User (tenanted)
│                 │
│                 ├── has_many ──► DailyLog
│                 └── has_many ──► ProjectMembership
│
├── has_many ──► Project (tenanted)
│                 │
│                 ├── has_many ──► DailyLog
│                 ├── has_many ──► ProjectMembership
│                 └── has_many ──► Integration
│
├── has_many ──► Integration (tenanted)
│                 └── has_many ──► IntegrationEvent
│
DailyLog (tenanted)
  ├── belongs_to ──► Organization
  ├── belongs_to ──► User (as :foreman)
  ├── belongs_to ──► Project
  └── has_many   ──► Photo

Photo (tenanted)
  ├── belongs_to ──► Organization
  └── belongs_to ──► DailyLog

ProjectMembership (tenanted)
  ├── belongs_to ──► Organization
  ├── belongs_to ──► User
  └── belongs_to ──► Project
```

---

## 3. SiteVoice.Accounts

### Domain Module

```elixir
defmodule SiteVoice.Accounts do
  use Ash.Domain

  resources do
    resource SiteVoice.Accounts.Organization
    resource SiteVoice.Accounts.User
    resource SiteVoice.Accounts.Token
  end
end
```

---

### `SiteVoice.Accounts.Organization`

The tenant root. Not itself tenanted. Lives in global scope. Created once per customer during registration.

```elixir
defmodule SiteVoice.Accounts.Organization do
  use Ash.Resource,
    domain: SiteVoice.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  # NO multitenancy block — this IS the tenant root

  postgres do
    table "organizations"
    repo  SiteVoice.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name,   :string, allow_nil?: false
    attribute :slug,   :string, allow_nil?: false   # unique, URL-safe, immutable after creation
    attribute :tier,   :atom,   allow_nil?: false,
      constraints: [one_of: [:pro, :enterprise]],
      default: :pro
    attribute :active, :boolean, default: true, allow_nil?: false

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end

  relationships do
    has_many :users,        SiteVoice.Accounts.User
    has_many :projects,     SiteVoice.Projects.Project
    has_many :integrations, SiteVoice.Integrations.Integration
  end

  actions do
    # Registration creates org + first user atomically — see RegisterOrganization action
    create :register do
      accept [:name]
      change SiteVoice.Accounts.Changes.GenerateSlug    # derives slug from name
      change set_attribute(:tier, :pro)
      change set_attribute(:active, true)
    end

    read :read do
      primary? true
    end

    read :get_by_slug do
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug))
    end

    update :update do
      accept [:name, :tier, :active]
    end
  end

  policies do
    # Only platform admins can list all organizations
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :platform_admin)
    end

    # Users can read their own organization (via get_by_id, not list)
    policy action(:read) do
      authorize_if expr(id == ^actor(:organization_id))
    end

    # Only platform admins can update tier; org_admin can update name
    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :platform_admin)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end

  json_api do
    type "organization"
    routes do
      base "/organizations"
      get  :read
      post :register
      patch :update
    end
  end
end
```

---

### `SiteVoice.Accounts.User`

Tenanted. The actor in all Ash Policy evaluations. Belongs to exactly one Organization.

```elixir
defmodule SiteVoice.Accounts.User do
  use Ash.Resource,
    domain: SiteVoice.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication, AshJsonApi.Resource, AshPaperTrail.Resource]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "users"
    repo  SiteVoice.Repo

    custom_indexes do
      # organization_id leads — critical for tenant query performance
      index [:organization_id]
      index [:organization_id, :email], unique: true
      index [:organization_id, :role]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id,    :uuid,   allow_nil?: false, public?: false
    attribute :email,              :string, allow_nil?: false
    attribute :hashed_password,    :string, allow_nil?: false, sensitive?: true, public?: false
    attribute :name,               :string, allow_nil?: false
    attribute :role,               :atom,   allow_nil?: false,
      constraints: [one_of: [:foreman, :pm, :owner, :org_admin]],
      default: :foreman
    attribute :preferred_language, :atom,
      constraints: [one_of: [:en, :es]],
      default: :en

    timestamps()
  end

  identities do
    # Email unique within organization, not globally
    identity :unique_email_per_org, [:organization_id, :email]
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    has_many   :daily_logs,   SiteVoice.Reporting.DailyLog,
      destination_attribute: :foreman_id
    has_many   :project_memberships, SiteVoice.Projects.ProjectMembership
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
      extra_token_fields   [:organization_id]   # included in every JWT claim
    end
  end

  actions do
    # Invite user into existing org (org_admin only)
    create :invite do
      accept [:email, :name, :role, :preferred_language]
      change set_attribute(:organization_id, actor(:organization_id))
      change SiteVoice.Accounts.Changes.HashPassword
    end

    read :read do
      primary? true
    end

    read :get_by_email do
      argument :email, :string, allow_nil?: false
      filter    expr(email == ^arg(:email))
    end

    update :update_profile do
      accept [:name, :preferred_language]
    end

    update :update_role do
      accept [:role]
    end

    destroy :destroy
  end

  policies do
    policy action(:invite) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:update_profile) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:update_role) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      forbid_if expr(id == ^actor(:id))   # can't delete yourself
    end
  end

  paper_trail do
    track_all_actions? true
  end

  json_api do
    type "user"
    routes do
      base "/users"
      index  :read
      get    :read
      post   :invite
      patch  :update_profile
      patch  :update_role
      delete :destroy
    end
  end
end
```

---

### `SiteVoice.Accounts.Token`

Global (not tenanted). Managed by AshAuthentication. Stores refresh tokens and revocation records.

```elixir
defmodule SiteVoice.Accounts.Token do
  use Ash.Resource,
    domain: SiteVoice.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  # NOT tenanted — global token store

  postgres do
    table "tokens"
    repo  SiteVoice.Repo
  end

  # AshAuthentication.TokenResource handles all attribute and action definitions
  # Do not add custom actions here
end
```

---

## 4. SiteVoice.Projects

### Domain Module

```elixir
defmodule SiteVoice.Projects do
  use Ash.Domain

  resources do
    resource SiteVoice.Projects.Project
    resource SiteVoice.Projects.ProjectMembership
  end
end
```

---

### `SiteVoice.Projects.Project`

Tenanted. A construction project (job site). The unit of reporting — daily logs belong to a project.

```elixir
defmodule SiteVoice.Projects.Project do
  use Ash.Resource,
    domain: SiteVoice.Projects,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshPaperTrail.Resource]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "projects"
    repo  SiteVoice.Repo

    custom_indexes do
      index [:organization_id]
      index [:organization_id, :code], unique: true
      index [:organization_id, :active]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid,    allow_nil?: false, public?: false
    attribute :name,            :string,  allow_nil?: false
    attribute :code,            :string,  allow_nil?: false   # e.g. "MERIDIAN-001"
    attribute :address,         :string
    attribute :timezone,        :string,  default: "America/Phoenix"
    attribute :active,          :boolean, default: true, allow_nil?: false

    timestamps()
  end

  identities do
    # Project code unique within organization
    identity :unique_code_per_org, [:organization_id, :code]
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    has_many   :daily_logs,   SiteVoice.Reporting.DailyLog
    has_many   :memberships,  SiteVoice.Projects.ProjectMembership
    has_many   :integrations, SiteVoice.Integrations.Integration
  end

  calculations do
    calculate :report_count, :integer, SiteVoice.Projects.Calculations.ReportCount
    calculate :last_report_date, :date, SiteVoice.Projects.Calculations.LastReportDate
  end

  actions do
    create :create do
      accept [:name, :code, :address, :timezone]
      change set_attribute(:organization_id, actor(:organization_id))
      change SiteVoice.Projects.Changes.NormalizeCode   # upcase, trim
    end

    read :read do
      primary? true
      prepare    build(load: [:report_count, :last_report_date])
    end

    read :list_active do
      filter expr(active == true)
    end

    update :update do
      accept [:name, :address, :timezone, :active]
    end

    destroy :archive do
      change set_attribute(:active, false)
      # soft delete — sets active: false, does not destroy record
    end
  end

  policies do
    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :owner)
      # Foremen can only read projects they are members of
      authorize_if relates_to_actor_via([:memberships, :user])
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action(:archive) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end

  paper_trail do
    track_all_actions? true
  end

  json_api do
    type "project"
    routes do
      base "/projects"
      index  :read
      get    :read
      post   :create
      patch  :update
      delete :archive
    end
  end
end
```

---

### `SiteVoice.Projects.ProjectMembership`

Tenanted. Join table between User and Project. Tracks which users are members of which projects, and their role on that project.

```elixir
defmodule SiteVoice.Projects.ProjectMembership do
  use Ash.Resource,
    domain: SiteVoice.Projects,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "project_memberships"
    repo  SiteVoice.Repo

    custom_indexes do
      index [:organization_id, :project_id, :user_id], unique: true
      index [:organization_id, :user_id]
      index [:organization_id, :project_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :role,            :atom,
      constraints: [one_of: [:foreman, :pm, :owner, :org_admin]],
      allow_nil?: false

    timestamps()
  end

  identities do
    identity :unique_membership, [:organization_id, :project_id, :user_id]
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    belongs_to :user,         SiteVoice.Accounts.User,         allow_nil?: false
    belongs_to :project,      SiteVoice.Projects.Project,      allow_nil?: false
  end

  actions do
    create :add_member do
      accept [:user_id, :project_id, :role]
      change set_attribute(:organization_id, actor(:organization_id))
    end

    read :read do
      primary? true
    end

    update :update_role do
      accept [:role]
    end

    destroy :remove_member
  end

  policies do
    policy action(:add_member) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action(:update_role) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:remove_member) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end
end
```

---

## 5. SiteVoice.Reporting

### Domain Module

```elixir
defmodule SiteVoice.Reporting do
  use Ash.Domain

  resources do
    resource SiteVoice.Reporting.DailyLog
    resource SiteVoice.Reporting.Photo
  end
end
```

---

### `SiteVoice.Reporting.DailyLog`

The core resource. Represents one foreman's daily site report. Drives the entire AI pipeline. See §10 for JSONB field schemas.

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

    custom_indexes do
      # organization_id leads all indexes
      index [:organization_id, :project_id, :date],     name: "daily_logs_org_project_date_idx"
      index [:organization_id, :foreman_id, :date],     name: "daily_logs_org_foreman_date_idx"
      index [:organization_id, :status],                name: "daily_logs_org_status_idx"
      index [:organization_id, :project_id, :status],   name: "daily_logs_org_project_status_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid,    allow_nil?: false, public?: false
    attribute :date,            :date,    allow_nil?: false
    attribute :status,          :atom,    allow_nil?: false,
      constraints: [one_of: [:pending, :processing, :draft, :submitted, :failed]],
      default: :pending

    # Storage
    attribute :audio_key,      :string   # Tigris key: {org_id}/{proj_id}/{date}/{id}.m4a
    attribute :audio_duration, :integer  # seconds

    # AI pipeline outputs
    attribute :transcript,     :string
    attribute :accuracy_score, :float    # 0.0 – 1.0 (Claude confidence)

    # Structured report sections (JSONB arrays)
    attribute :labor,     {:array, :map}, default: []
    attribute :progress,  {:array, :map}, default: []
    attribute :equipment, {:array, :map}, default: []
    attribute :materials, {:array, :map}, default: []
    attribute :delays,    {:array, :map}, default: []
    attribute :safety,    {:array, :map}, default: []

    # PDF output
    attribute :pdf_key,   :string        # Tigris key: {org_id}/{proj_id}/{year}/{month}/{id}.pdf

    # Optional metadata
    attribute :weather,   :string        # manually entered by foreman

    attribute :submitted_at, :utc_datetime

    timestamps()
  end

  identities do
    # One log per foreman per project per date
    identity :unique_log_per_day, [:organization_id, :date, :foreman_id, :project_id]
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    belongs_to :foreman,      SiteVoice.Accounts.User,         allow_nil?: false,
      attribute_writable?: true
    belongs_to :project,      SiteVoice.Projects.Project,      allow_nil?: false
    has_many   :photos,       SiteVoice.Reporting.Photo
  end

  calculations do
    calculate :pdf_url,   :string,  SiteVoice.Reporting.Calculations.PdfUrl
    calculate :audio_url, :string,  SiteVoice.Reporting.Calculations.AudioUrl
    calculate :is_late,   :boolean, SiteVoice.Reporting.Calculations.IsLate
    # :is_late — true if submitted after 6 PM on the report date
  end

  # ── Actions ──────────────────────────────────────────────────

  actions do
    # Foreman submits audio recording — triggers Oban pipeline
    create :submit_recording do
      accept [:date, :audio_key, :audio_duration, :weather]

      argument :project_id, :uuid, allow_nil?: false

      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:foreman_id,      actor(:id))
      change set_attribute(:status,          :pending)
      change manage_relationship(:project_id, :project, type: :append)
      change SiteVoice.Reporting.Changes.EnqueueProcessing
    end

    # Reactor step 3 — Whisper transcript received
    update :apply_transcript do
      accept [:transcript]
      change set_attribute(:status, :processing)
    end

    # Reactor step 6 — Claude structured output received
    update :apply_structure do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :accuracy_score]
      change set_attribute(:status, :draft)
    end

    # Foreman reviews and submits
    update :approve_and_submit do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :weather]
      change set_attribute(:status, :submitted)
      change set_attribute(:submitted_at, &DateTime.utc_now/0)
      change SiteVoice.Reporting.Changes.DispatchIntegrations
    end

    # Reactor compensation — pipeline failed
    update :mark_failed do
      change set_attribute(:status, :failed)
    end

    # Foreman edits a draft before submission
    update :edit_draft do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :weather, :pdf_key]
    end

    read :read do
      primary? true
      prepare    build(load: [:pdf_url, :photos])
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter    expr(project_id == ^arg(:project_id))
      prepare   build(sort: [date: :desc])
    end

    read :list_for_date_range do
      argument :project_id, :uuid, allow_nil?: false
      argument :from,       :date, allow_nil?: false
      argument :to,         :date, allow_nil?: false
      filter    expr(
        project_id == ^arg(:project_id) and
        date >= ^arg(:from) and
        date <= ^arg(:to)
      )
      prepare build(sort: [date: :desc])
    end

    destroy :destroy do
      # Soft guard — only pre-submission logs can be deleted
      change before_action(fn changeset, _ ->
        if changeset.data.status == :submitted do
          Ash.Changeset.add_error(changeset, "Cannot delete a submitted log")
        else
          changeset
        end
      end)
    end
  end

  # ── Policies ─────────────────────────────────────────────────

  policies do
    policy action(:submit_recording) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action([:apply_transcript, :apply_structure, :mark_failed]) do
      # Internal pipeline actions — only system (no actor) or org_admin
      authorize_if actor_is_nil()
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:edit_draft) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:approve_and_submit) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:read) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end

    policy action(:destroy) do
      forbid_if attribute_equals(:status, :submitted)
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end

  paper_trail do
    track_all_actions? true
  end

  json_api do
    type "daily_log"
    routes do
      base "/daily-logs"
      index  :read
      get    :read
      post   :submit_recording
      patch  :approve_and_submit
      patch  :edit_draft
      delete :destroy
    end
  end
end
```

#### DailyLog State Machine

```
:pending ──submit_recording──► :pending
                                    │
                             Oban enqueues
                             AudioProcessor
                                    │
                         apply_transcript
                                    │
                                    ▼
                             :processing
                                    │
                          apply_structure
                                    │
                                    ▼
                               :draft ◄────── edit_draft (loopback)
                                    │
                         approve_and_submit
                                    │
                                    ▼
                             :submitted  (terminal — no transitions out)

  Any state ──mark_failed──► :failed
  (except :submitted)        (retriable via Oban retry)
```

---

### `SiteVoice.Reporting.Photo`

Tenanted. A site photo attached to a DailyLog. Caption and category are AI-generated by Claude Vision during the Reactor pipeline.

```elixir
defmodule SiteVoice.Reporting.Photo do
  use Ash.Resource,
    domain: SiteVoice.Reporting,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "photos"
    repo  SiteVoice.Repo

    custom_indexes do
      index [:organization_id, :daily_log_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid,   allow_nil?: false, public?: false
    attribute :storage_key,     :string, allow_nil?: false  # Tigris key — org-prefixed
    attribute :caption,         :string  # AI-generated by Claude Vision
    attribute :category,        :atom,
      constraints: [one_of: [:progress, :equipment, :delays, :safety, :materials]]
    attribute :taken_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    belongs_to :daily_log,    SiteVoice.Reporting.DailyLog,    allow_nil?: false
  end

  calculations do
    calculate :url, :string, SiteVoice.Reporting.Calculations.PhotoUrl
    # Returns a 1-hour presigned Tigris URL for the photo
  end

  actions do
    create :upload do
      accept [:storage_key, :taken_at]
      argument :daily_log_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, actor(:organization_id))
      change manage_relationship(:daily_log_id, :daily_log, type: :append)
    end

    # Called by Reactor caption_photos step (no actor)
    update :apply_caption do
      accept [:caption, :category]
    end

    read :read do
      primary? true
      prepare    build(load: [:url])
    end

    destroy :destroy
  end

  policies do
    policy action(:upload) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action(:apply_caption) do
      authorize_if actor_is_nil()    # Reactor step — no actor
    end

    policy action(:read) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:destroy) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end

  json_api do
    type "photo"
    routes do
      base "/photos"
      get    :read
      post   :upload
      delete :destroy
    end
  end
end
```

---

## 6. SiteVoice.Integrations

### Domain Module

```elixir
defmodule SiteVoice.Integrations do
  use Ash.Domain

  resources do
    resource SiteVoice.Integrations.Integration
    resource SiteVoice.Integrations.IntegrationEvent
  end
end
```

---

### `SiteVoice.Integrations.Integration`

Tenanted. Stores connection config for external systems (Procore, ACC, Slack, email). Config is encrypted at rest. One integration per provider per organization.

```elixir
defmodule SiteVoice.Integrations.Integration do
  use Ash.Resource,
    domain: SiteVoice.Integrations,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "integrations"
    repo  SiteVoice.Repo

    custom_indexes do
      index [:organization_id]
      index [:organization_id, :provider], unique: true
      index [:organization_id, :active]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :provider, :atom, allow_nil?: false,
      constraints: [one_of: [:procore, :autodesk_acc, :slack, :email]]
    attribute :config,  :map,    default: %{},
      sensitive?: true    # encrypted at rest — never logged
    attribute :active,  :boolean, default: true

    timestamps()
  end

  identities do
    identity :unique_provider_per_org, [:organization_id, :provider]
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    belongs_to :project,      SiteVoice.Projects.Project
    has_many   :events,       SiteVoice.Integrations.IntegrationEvent
  end

  actions do
    create :connect do
      accept [:provider, :config, :project_id]
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:active, true)
    end

    read :read do
      primary? true
      # config field redacted in serialization — never expose tokens
      prepare build(select: [:id, :provider, :active, :project_id, :inserted_at])
    end

    update :update_config do
      accept [:config]
    end

    update :toggle_active do
      accept [:active]
    end

    destroy :disconnect
  end

  policies do
    policy action([:connect, :update_config, :toggle_active, :disconnect]) do
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end
  end

  json_api do
    type "integration"
    routes do
      base "/integrations"
      index  :read
      post   :connect
      patch  :update_config
      patch  :toggle_active
      delete :disconnect
    end
  end
end
```

---

### `SiteVoice.Integrations.IntegrationEvent`

Tenanted. Immutable audit log of every push attempt to an external system. Used for debugging and retry visibility.

```elixir
defmodule SiteVoice.Integrations.IntegrationEvent do
  use Ash.Resource,
    domain: SiteVoice.Integrations,
    data_layer: AshPostgres.DataLayer

  multitenancy do
    strategy  :attribute
    attribute :organization_id
  end

  postgres do
    table "integration_events"
    repo  SiteVoice.Repo

    custom_indexes do
      index [:organization_id, :integration_id, :inserted_at]
      index [:organization_id, :daily_log_id]
      index [:organization_id, :status]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :status,          :atom, allow_nil?: false,
      constraints: [one_of: [:success, :failed, :pending]]
    attribute :request_body,    :map,  sensitive?: true
    attribute :response_body,   :map,  sensitive?: true
    attribute :error_message,   :string
    attribute :attempted_at,    :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :organization, SiteVoice.Accounts.Organization, allow_nil?: false
    belongs_to :integration,  SiteVoice.Integrations.Integration, allow_nil?: false
    belongs_to :daily_log,    SiteVoice.Reporting.DailyLog, allow_nil?: false
  end

  actions do
    create :record do
      accept [:integration_id, :daily_log_id, :status,
              :request_body, :response_body, :error_message, :attempted_at]
      change set_attribute(:organization_id, actor(:organization_id))
    end

    read :read do
      primary? true
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action(:record) do
      authorize_if actor_is_nil()    # Oban worker — no actor
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end
  end
end
```

---

## 7. SiteVoice.Admin

Platform admin domain. No multitenancy — reads across all tenants. **Never exposed via the public AshJsonApi router.** Accessed only via internal admin tooling.

```elixir
defmodule SiteVoice.Admin do
  use Ash.Domain

  resources do
    resource SiteVoice.Admin.Organization
    resource SiteVoice.Admin.DailyLog
  end
end

# Example admin resource — no multitenancy block
defmodule SiteVoice.Admin.DailyLog do
  use Ash.Resource,
    domain: SiteVoice.Admin,
    data_layer: AshPostgres.DataLayer

  # NO multitenancy block — sees all rows across all tenants

  postgres do
    table "daily_logs"    # same table, no tenant filter
    repo  SiteVoice.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid
    attribute :status,          :atom
    attribute :date,            :date
    attribute :accuracy_score,  :float
    timestamps()
  end

  actions do
    read :read do
      primary? true
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :platform_admin)
    end
  end
end
```

---

## 8. Changes Reference

Custom `Ash.Resource.Change` modules. All located in `lib/site_voice/{domain}/resources/changes/`.

| Module | Used In | Purpose |
|---|---|---|
| `Accounts.Changes.GenerateSlug` | Organization `:register` | Derives URL-safe slug from org name |
| `Accounts.Changes.HashPassword` | User `:invite` | Bcrypt hashes raw password before save |
| `Projects.Changes.NormalizeCode` | Project `:create` | Upcases and trims project code |
| `Reporting.Changes.EnqueueProcessing` | DailyLog `:submit_recording` | Inserts Oban job after successful create |
| `Reporting.Changes.DispatchIntegrations` | DailyLog `:approve_and_submit` | Inserts Oban jobs for Procore, email |

### `EnqueueProcessing` — Detail

This is the most critical Change. It fires after the DailyLog is successfully created and enqueues the Oban worker with `organization_id` explicitly in args.

```elixir
defmodule SiteVoice.Reporting.Changes.EnqueueProcessing do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      %{
        log_id:          log.id,
        organization_id: log.organization_id   # MUST always be present
      }
      |> SiteVoice.Workers.AudioProcessor.new()
      |> Oban.insert!()

      {:ok, log}
    end)
  end
end
```

### `DispatchIntegrations` — Detail

Fires after `:approve_and_submit`. Inserts one Oban job per active integration on the project.

```elixir
defmodule SiteVoice.Reporting.Changes.DispatchIntegrations do
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _changeset, log ->
      log.project
      |> Ash.load!(:integrations)
      |> Map.get(:integrations, [])
      |> Enum.filter(& &1.active)
      |> Enum.each(fn integration ->
        %{
          log_id:           log.id,
          integration_id:   integration.id,
          organization_id:  log.organization_id
        }
        |> SiteVoice.Workers.IntegrationDispatcher.new()
        |> Oban.insert!()
      end)

      {:ok, log}
    end)
  end
end
```

---

## 9. Calculations Reference

Custom `Ash.Resource.Calculation` modules. Located in `lib/site_voice/{domain}/resources/calculations/`.

| Module | Resource | Return Type | Purpose |
|---|---|---|---|
| `Reporting.Calculations.PdfUrl` | DailyLog | `:string` | Presigned Tigris URL for PDF (1hr expiry) |
| `Reporting.Calculations.AudioUrl` | DailyLog | `:string` | Presigned Tigris URL for audio (admin only) |
| `Reporting.Calculations.IsLate` | DailyLog | `:boolean` | True if submitted after 6 PM on report date |
| `Reporting.Calculations.PhotoUrl` | Photo | `:string` | Presigned Tigris URL for photo (1hr expiry) |
| `Projects.Calculations.ReportCount` | Project | `:integer` | Count of submitted DailyLogs for project |
| `Projects.Calculations.LastReportDate` | Project | `:date` | Date of most recent submitted DailyLog |

### `PdfUrl` — Detail

```elixir
defmodule SiteVoice.Reporting.Calculations.PdfUrl do
  use Ash.Resource.Calculation

  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.pdf_key do
        nil -> nil
        key ->
          {:ok, url} = SiteVoice.Storage.presigned_url("sitevoice-pdfs", key, 3600)
          url
      end
    end)
  end
end
```

---

## 10. JSONB Field Schemas

The six report section attributes on `DailyLog` are `{:array, :map}` stored as JSONB. Each map in the array follows a defined schema. Claude is prompted to produce output matching these schemas exactly.

### Labor Entry

```json
{
  "crew":          "Martinez",
  "headcount":     6,
  "trade":         "Rebar installation",
  "hours":         "07:00-16:00",
  "subcontractor": true
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `crew` | string | yes | Crew name or company |
| `headcount` | integer | yes | Number of workers |
| `trade` | string | yes | Work type |
| `hours` | string | no | e.g. "07:00-16:00" |
| `subcontractor` | boolean | no | Defaults false |

### Progress Entry

```json
{
  "description":        "North wall framing approximately 80% complete",
  "location":           "Level 4",
  "percentage_complete": 80
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `description` | string | yes | What was accomplished |
| `location` | string | no | Level, zone, or area |
| `percentage_complete` | integer | no | 0–100 |

### Equipment Entry

```json
{
  "item":   "Crane 2",
  "status": "offline",
  "note":   "Hydraulic issue, resolved 12:00 PM"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `item` | string | yes | Equipment name |
| `status` | string | yes | "operational" \| "offline" \| "idle" \| "on_order" |
| `note` | string | no | Additional context |

### Materials Entry

```json
{
  "item":        "Concrete 4000 PSI",
  "quantity":    "8 yards",
  "received_at": "14:00",
  "note":        "No issues — driver signed"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `item` | string | yes | Material name |
| `quantity` | string | no | Amount with units |
| `received_at` | string | no | Time received |
| `note` | string | no | Delivery notes |

### Delays Entry

```json
{
  "description": "Crane 2 offline AM — approximately 3 hours lost",
  "cause":       "Equipment failure",
  "impact":      "Level 4 framing schedule delayed",
  "hours_lost":  3
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `description` | string | yes | What happened |
| `cause` | string | no | Root cause |
| `impact` | string | no | Downstream effect |
| `hours_lost` | number | no | Estimated hours lost |

### Safety Entry

```json
{
  "description":   "Morning toolbox talk completed. No incidents. Harness check 07:15.",
  "incident_type": "none"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `description` | string | yes | Safety observation |
| `incident_type` | string | no | "none" \| "near_miss" \| "first_aid" \| "recordable" |

---

## 11. Policy Matrix

Summary of which roles can perform which actions across resources. Tenant scoping (organization_id) is applied before any policy check — policies express user-level rules only.

| Resource | Action | foreman | pm | owner | org_admin | platform_admin | no actor |
|---|---|---|---|---|---|---|---|
| Organization | :register | — | — | — | — | ✓ | ✓ |
| Organization | :read (own) | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| Organization | :update | — | — | — | ✓ | ✓ | — |
| User | :invite | — | — | — | ✓ | — | — |
| User | :read | self only | ✓ | — | ✓ | — | — |
| User | :update_profile | self only | self only | self only | ✓ | — | — |
| User | :update_role | — | — | — | ✓ | — | — |
| Project | :create | — | ✓ | — | ✓ | — | — |
| Project | :read | member only | ✓ | ✓ | ✓ | — | — |
| Project | :update | — | ✓ | — | ✓ | — | — |
| ProjectMembership | :add_member | — | ✓ | — | ✓ | — | — |
| DailyLog | :submit_recording | ✓ | ✓ | — | ✓ | — | — |
| DailyLog | :apply_transcript | — | — | — | — | — | ✓ |
| DailyLog | :apply_structure | — | — | — | — | — | ✓ |
| DailyLog | :edit_draft | own only | — | — | ✓ | — | — |
| DailyLog | :approve_and_submit | own only | — | — | ✓ | — | — |
| DailyLog | :read | own only | ✓ | ✓ | ✓ | — | — |
| DailyLog | :destroy | own+pre-submit | — | — | ✓ | — | — |
| Photo | :upload | ✓ | ✓ | — | ✓ | — | — |
| Photo | :apply_caption | — | — | — | — | — | ✓ |
| Photo | :read | own log only | ✓ | — | ✓ | — | — |
| Integration | :connect | — | — | — | ✓ | — | — |
| Integration | :read | — | ✓ | — | ✓ | — | — |
| IntegrationEvent | :record | — | — | — | — | — | ✓ |
| IntegrationEvent | :read | — | ✓ | — | ✓ | — | — |

**Legend:**
- ✓ — authorized
- — — not authorized
- own only — authorized for records the actor owns
- self only — authorized for actor's own record
- member only — authorized if actor is a project member
- own+pre-submit — authorized if actor owns the record AND status ≠ :submitted
- no actor — Oban workers / Reactor steps operate without an actor

---

## 12. AshJsonApi Route Map

All routes are implicitly tenant-scoped via the SetTenant plug. `organization_id` never appears in route params.

```
Base: https://api.sitevoice.app/api

Organizations
  POST   /organizations               Organization :register
  GET    /organizations/me            Organization :read (own)
  PATCH  /organizations/me            Organization :update

Auth (AshAuthentication)
  POST   /auth/sign-in                password strategy sign-in
  POST   /auth/refresh                token refresh
  DELETE /auth/sign-out               sign out

Users
  GET    /users                       User :read (list, pm/org_admin)
  GET    /users/:id                   User :read
  POST   /users                       User :invite (org_admin)
  PATCH  /users/:id/profile           User :update_profile
  PATCH  /users/:id/role              User :update_role
  DELETE /users/:id                   User :destroy (org_admin)

Projects
  GET    /projects                    Project :read (list)
  GET    /projects/:id                Project :read
  POST   /projects                    Project :create
  PATCH  /projects/:id                Project :update
  DELETE /projects/:id                Project :archive

Project Memberships
  GET    /projects/:id/memberships    ProjectMembership :read
  POST   /projects/:id/memberships    ProjectMembership :add_member
  PATCH  /memberships/:id             ProjectMembership :update_role
  DELETE /memberships/:id             ProjectMembership :remove_member

Daily Logs
  GET    /daily-logs                  DailyLog :read (list)
  GET    /daily-logs/:id              DailyLog :read
  POST   /daily-logs                  DailyLog :submit_recording
  PATCH  /daily-logs/:id/draft        DailyLog :edit_draft
  PATCH  /daily-logs/:id/submit       DailyLog :approve_and_submit
  DELETE /daily-logs/:id              DailyLog :destroy

Photos
  GET    /daily-logs/:id/photos       Photo :read (list for log)
  GET    /photos/:id                  Photo :read
  POST   /daily-logs/:id/photos       Photo :upload
  DELETE /photos/:id                  Photo :destroy

Integrations
  GET    /integrations                Integration :read
  POST   /integrations                Integration :connect
  PATCH  /integrations/:id/config     Integration :update_config
  PATCH  /integrations/:id/toggle     Integration :toggle_active
  DELETE /integrations/:id            Integration :disconnect
```

---

*This document is generated from agreed resource designs as of May 2025. All resources are created via `mix ash.gen.resource` and managed through Ash migrations. When adding a new resource, update this document alongside the resource file.*
