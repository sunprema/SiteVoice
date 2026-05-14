defmodule Sitevoice.Accounts.Organization do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Sitevoice.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :tier, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:pro, :enterprise]],
      default: :pro

    attribute :active, :boolean, allow_nil?: false, public?: true, default: true

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end

  relationships do
    has_many :users, Sitevoice.Accounts.User
    has_many :projects, Sitevoice.Projects.Project
  end

  actions do
    create :register do
      accept [:name]
      change Sitevoice.Accounts.Changes.GenerateSlug
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
    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :platform_admin)
      authorize_if expr(id == ^actor(:organization_id))
    end

    policy action(:update) do
      authorize_if actor_attribute_equals(:role, :platform_admin)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:register) do
      authorize_if always()
    end
  end
end
