defmodule Sitevoice.Projects.Project do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource, AshPaperTrail.Resource],
    primary_read_warning?: false

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "projects"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id]
      index [:organization_id, :code], unique: true
      index [:organization_id, :active]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :address, :string, public?: true
    attribute :timezone, :string, default: "America/Phoenix", public?: true
    attribute :active, :boolean, default: true, allow_nil?: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_code_per_org, [:organization_id, :code]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization,
      allow_nil?: false,
      define_attribute?: false

    has_many :memberships, Sitevoice.Projects.ProjectMembership
  end

  calculations do
    calculate :report_count, :integer, Sitevoice.Projects.Calculations.ReportCount
    calculate :last_report_date, :date, Sitevoice.Projects.Calculations.LastReportDate
  end

  actions do
    create :create do
      accept [:name, :code, :address, :timezone]
      change set_attribute(:organization_id, actor(:organization_id))
      change Sitevoice.Projects.Changes.NormalizeCode
    end

    read :read do
      primary? true
      prepare build(load: [:report_count, :last_report_date])
    end

    read :list_active do
      filter expr(active == true)
    end

    update :update do
      accept [:name, :address, :timezone, :active]
    end

    destroy :archive do
      soft? true
      change set_attribute(:active, false)
    end
  end

  policies do
    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action([:read, :list_active]) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :owner)
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
    store_action_name? true
    attributes_as_attributes [:organization_id]
  end

  json_api do
    type "project"
    routes do
      base "/projects"
      index :read
      get :read
      post :create
      patch :update
      delete :archive
    end
  end
end
