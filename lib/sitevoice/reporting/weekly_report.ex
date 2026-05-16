defmodule Sitevoice.Reporting.WeeklyReport do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Reporting,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "weekly_reports"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :project_id, :week_start], name: "weekly_reports_org_project_week_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :week_start, :date, allow_nil?: false
    attribute :week_end, :date, allow_nil?: false
    attribute :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:pending, :generating, :ready, :failed]],
      default: :pending

    attribute :summary, :string
    attribute :key_accomplishments, {:array, :string}, default: []
    attribute :outstanding_issues, {:array, :string}, default: []
    attribute :trends, {:array, :map}, default: []
    attribute :total_labor_hours, :float
    attribute :total_headcount_days, :integer
    attribute :daily_log_count, :integer
    attribute :pdf_key, :string
    attribute :generated_at, :utc_datetime

    timestamps()
  end

  identities do
    identity :unique_report_per_week, [:organization_id, :project_id, :week_start]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :project, Sitevoice.Projects.Project, allow_nil?: false
  end

  calculations do
    calculate :pdf_url, :string, Sitevoice.Reporting.Calculations.WeeklyPdfUrl
  end

  actions do
    create :create do
      accept [:week_start, :week_end]
      argument :project_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:project_id, arg(:project_id))
    end

    update :mark_generating do
      change set_attribute(:status, :generating)
    end

    update :mark_ready do
      accept [
        :summary,
        :key_accomplishments,
        :outstanding_issues,
        :trends,
        :pdf_key,
        :total_labor_hours,
        :total_headcount_days,
        :daily_log_count,
        :generated_at
      ]
      change set_attribute(:status, :ready)
    end

    update :mark_failed do
      change set_attribute(:status, :failed)
    end

    read :read do
      primary? true
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [week_start: :desc])
    end

    read :get_by_week do
      argument :project_id, :uuid, allow_nil?: false
      argument :week_start, :date, allow_nil?: false
      filter expr(project_id == ^arg(:project_id) and week_start == ^arg(:week_start))
      prepare build(limit: 1)
    end
  end

  policies do
    policy action([:create, :mark_generating, :mark_ready, :mark_failed]) do
      authorize_if actor_absent()
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:read, :list_for_project, :get_by_week]) do
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :owner)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end
end
