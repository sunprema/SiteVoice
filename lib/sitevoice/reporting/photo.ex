defmodule Sitevoice.Reporting.Photo do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Reporting,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    primary_read_warning?: false

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "photos"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :daily_log_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :storage_key, :string, allow_nil?: false
    attribute :caption, :string
    attribute :category, :atom,
      constraints: [one_of: [:progress, :equipment, :delays, :safety, :materials]]
    attribute :taken_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :daily_log, Sitevoice.Reporting.DailyLog, allow_nil?: false
  end

  calculations do
    calculate :url, :string, Sitevoice.Reporting.Calculations.PhotoUrl
  end

  actions do
    create :upload do
      accept [:storage_key, :taken_at]
      argument :daily_log_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
    end

    update :apply_caption do
      accept [:caption, :category]
    end

    read :read do
      primary? true
      prepare build(load: [:url])
    end

    destroy :destroy
  end

  policies do
    policy action(:upload) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:apply_caption) do
      authorize_if actor_absent()
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
      get :read
      post :upload
      delete :destroy
    end
  end
end
