defmodule Sitevoice.Integrations.Integration do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Integrations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "integrations"
    repo Sitevoice.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :provider, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:procore]]

    attribute :config, :map, allow_nil?: false, public?: false

    attribute :active, :boolean, allow_nil?: false, default: true, public?: true

    timestamps()
  end

  actions do
    read :read do
      primary? true
    end

    read :list_active do
      filter expr(active == true)
    end

    create :create do
      accept [:provider, :config, :active]
      change set_attribute(:organization_id, actor(:organization_id))
    end

    update :update do
      accept [:config, :active]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :foreman)
    end

    policy action(:create) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end

    policy action(:destroy) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end
  end
end
