defmodule Sitevoice.Projects.ProjectMembership do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "project_memberships"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :project_id, :user_id], unique: true
      index [:organization_id, :user_id]
      index [:organization_id, :project_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :role, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:foreman, :pm, :owner, :org_admin]]

    timestamps()
  end

  identities do
    identity :unique_membership, [:organization_id, :project_id, :user_id]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization,
      allow_nil?: false,
      define_attribute?: false

    belongs_to :user, Sitevoice.Accounts.User, allow_nil?: false
    belongs_to :project, Sitevoice.Projects.Project, allow_nil?: false
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
