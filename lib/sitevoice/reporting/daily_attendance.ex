defmodule Sitevoice.Reporting.DailyAttendance do
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
    table "daily_attendances"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :daily_log_id], name: "daily_attendances_org_log_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :headcount_present, :integer, allow_nil?: false, default: 0
    attribute :headcount_absent, :integer, allow_nil?: false, default: 0
    attribute :hours, :float, allow_nil?: false, default: 8.0
    attribute :notes, :string

    timestamps()
  end

  identities do
    identity :unique_log_crew, [:organization_id, :daily_log_id, :crew_template_id]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :daily_log, Sitevoice.Reporting.DailyLog, allow_nil?: false
    belongs_to :crew_template, Sitevoice.Reporting.CrewTemplate, allow_nil?: false
  end

  actions do
    create :create do
      accept [:headcount_present, :headcount_absent, :hours, :notes]
      argument :daily_log_id, :uuid, allow_nil?: false
      argument :crew_template_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
      change set_attribute(:crew_template_id, arg(:crew_template_id))
    end

    create :create_from_system do
      accept [:headcount_present, :headcount_absent, :hours]
      argument :daily_log_id, :uuid, allow_nil?: false
      argument :crew_template_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
      change set_attribute(:crew_template_id, arg(:crew_template_id))
    end

    update :update_attendance do
      accept [:headcount_present, :headcount_absent, :hours, :notes]
    end

    read :read do
      primary? true
    end

    read :list_for_log do
      argument :daily_log_id, :uuid, allow_nil?: false
      filter expr(daily_log_id == ^arg(:daily_log_id))
      prepare build(load: [:crew_template], sort: [inserted_at: :asc])
    end
  end

  policies do
    policy action([:create]) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:create_from_system]) do
      authorize_if actor_absent()
    end

    policy action([:update_attendance]) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:read, :list_for_log]) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end
  end
end
