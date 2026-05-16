defmodule Sitevoice.Reporting.CrewTemplate do
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
    table "crew_templates"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :project_id], name: "crew_templates_org_project_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :name, :string, allow_nil?: false

    attribute :trade, :atom,
      constraints: [one_of: [:concrete, :framing, :electrical, :plumbing, :steel, :hvac, :general]],
      default: :general

    attribute :subcontractor, :string

    attribute :default_headcount, :integer, allow_nil?: false, default: 1

    attribute :active, :boolean, allow_nil?: false, default: true

    timestamps()
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :project, Sitevoice.Projects.Project, allow_nil?: false
  end

  actions do
    create :create do
      accept [:name, :trade, :subcontractor, :default_headcount]
      argument :project_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:project_id, arg(:project_id))
    end

    update :update do
      accept [:name, :trade, :subcontractor, :default_headcount, :active]
    end

    destroy :destroy

    read :read do
      primary? true
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id) and active == true)
      prepare build(sort: [name: :asc])
    end

    read :list_all_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:read, :list_for_project, :list_all_for_project]) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end
  end
end
