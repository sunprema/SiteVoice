defmodule Sitevoice.Integrations.IntegrationEvent do
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
    table "integration_events"
    repo Sitevoice.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :integration_id, :uuid, allow_nil?: false, public?: true

    attribute :log_id, :uuid, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:pending, :sent, :failed]]

    attribute :payload, :map, allow_nil?: false, public?: true

    attribute :response, :map, allow_nil?: true, public?: true

    timestamps()
  end

  actions do
    read :read do
      primary? true
    end

    create :create do
      accept [:integration_id, :log_id, :status, :payload, :response, :organization_id]
    end

    update :update do
      accept [:status, :response]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    # create/update are system-only; worker calls with authorize?: false
    policy action(:create) do
      forbid_if always()
    end

    policy action(:update) do
      forbid_if always()
    end
  end
end
