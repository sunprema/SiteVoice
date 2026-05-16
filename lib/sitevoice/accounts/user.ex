defmodule Sitevoice.Accounts.User do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshPaperTrail.Resource]

  multitenancy do
    strategy :attribute
    attribute :organization_id
    # global? true allows sign_in_with_password to find users without a tenant;
    # the tenant is in the JWT, not the request — callers can't provide it upfront
    global? true
  end

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end

      confirmation :confirm_new_user do
        monitor_fields [:email]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at
        auto_confirm_actions [:reset_password_with_token]
        sender Sitevoice.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end

    tokens do
      enabled? true
      token_resource Sitevoice.Accounts.Token
      signing_secret Sitevoice.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider

        resettable do
          sender Sitevoice.Accounts.User.Senders.SendPasswordResetEmail
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end

      remember_me :remember_me

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end
    end
  end

  postgres do
    table "users"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id]
      index [:organization_id, :email], unique: true
      index [:organization_id, :role]
    end
  end

  paper_trail do
    attributes_as_attributes [:organization_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :role, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:foreman, :pm, :owner, :org_admin]],
      default: :foreman

    attribute :preferred_language, :atom,
      public?: true,
      constraints: [one_of: [:en, :es]],
      default: :en

    attribute :active, :boolean, allow_nil?: false, public?: true, default: true

    attribute :invited_at, :utc_datetime_usec, allow_nil?: true, public?: false

    attribute :confirmed_at, :utc_datetime_usec
    timestamps()
  end

  identities do
    # AshAuthentication requires a global unique identity on the identity field
    identity :unique_email, [:email]
    # Additional per-org constraint for multitenancy semantics
    identity :unique_email_per_org, [:organization_id, :email]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization,
      allow_nil?: false,
      define_attribute?: false

    has_many :valid_api_keys, Sitevoice.Accounts.ApiKey do
      filter expr(valid)
    end

    has_many :project_memberships, Sitevoice.Projects.ProjectMembership
  end

  actions do
    read :read do
      primary? true
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      filter expr(active == true)

      prepare Sitevoice.Accounts.Preparations.SetTenantMetadata
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      prepare Sitevoice.Accounts.Preparations.SetTenantFromSignInToken
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      argument :organization_id, :uuid do
        allow_nil? false
      end

      argument :name, :string do
        allow_nil? false
      end

      argument :role, :atom do
        constraints [one_of: [:foreman, :pm, :owner, :org_admin]]
        default :org_admin
      end

      change set_attribute(:email, arg(:email))
      change set_attribute(:organization_id, arg(:organization_id))
      change set_attribute(:name, arg(:name))
      change set_attribute(:role, arg(:role))

      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange

      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :invite do
      accept [:email, :name, :role, :preferred_language]
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:invited_at, &DateTime.utc_now/0)
      change Sitevoice.Accounts.Changes.HashPassword
      change Sitevoice.Accounts.Changes.SendInvitationEmail
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    update :change_password do
      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :reset_password_with_token do
      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      validate AshAuthentication.Strategy.Password.ResetTokenValidation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation
      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end

    update :update_profile do
      accept [:name, :preferred_language]
    end

    update :update_role do
      accept [:role]
    end

    update :deactivate do
      accept []
      change set_attribute(:active, false)
    end

    update :reactivate do
      accept []
      change set_attribute(:active, true)
    end

    destroy :destroy
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:invite) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
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
      forbid_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:deactivate) do
      forbid_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end

    policy action(:reactivate) do
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end
  end
end
