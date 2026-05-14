defmodule Sitevoice.Reporting.DailyLog do
  use Ash.Resource,
    otp_app: :sitevoice,
    domain: Sitevoice.Reporting,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource, AshPaperTrail.Resource],
    primary_read_warning?: false

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  postgres do
    table "daily_logs"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :project_id, :date], name: "daily_logs_org_project_date_idx"
      index [:organization_id, :foreman_id, :date], name: "daily_logs_org_foreman_date_idx"
      index [:organization_id, :status], name: "daily_logs_org_status_idx"
      index [:organization_id, :project_id, :status], name: "daily_logs_org_project_status_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false
    attribute :date, :date, allow_nil?: false
    attribute :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:pending, :processing, :draft, :submitted, :failed]],
      default: :pending

    attribute :audio_key, :string
    attribute :audio_duration, :integer
    attribute :transcript, :string
    attribute :accuracy_score, :float
    attribute :labor, {:array, :map}, default: []
    attribute :progress, {:array, :map}, default: []
    attribute :equipment, {:array, :map}, default: []
    attribute :materials, {:array, :map}, default: []
    attribute :delays, {:array, :map}, default: []
    attribute :safety, {:array, :map}, default: []
    attribute :pdf_key, :string
    attribute :weather, :string
    attribute :submitted_at, :utc_datetime

    timestamps()
  end

  identities do
    identity :unique_log_per_day, [:organization_id, :date, :foreman_id, :project_id]
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :foreman, Sitevoice.Accounts.User, allow_nil?: false, attribute_writable?: true
    belongs_to :project, Sitevoice.Projects.Project, allow_nil?: false
    has_many :photos, Sitevoice.Reporting.Photo
  end

  calculations do
    calculate :pdf_url, :string, Sitevoice.Reporting.Calculations.PdfUrl
    calculate :audio_url, :string, Sitevoice.Reporting.Calculations.AudioUrl
    calculate :is_late, :boolean, Sitevoice.Reporting.Calculations.IsLate
  end

  actions do
    create :submit_recording do
      accept [:date, :audio_key, :audio_duration, :weather]

      argument :project_id, :uuid, allow_nil?: false

      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:foreman_id, actor(:id))
      change set_attribute(:status, :pending)
      change set_attribute(:project_id, arg(:project_id))
      change Sitevoice.Reporting.Changes.EnqueueProcessing
    end

    update :apply_transcript do
      accept [:transcript]
      change set_attribute(:status, :processing)
    end

    update :apply_structure do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :accuracy_score]
      change set_attribute(:status, :draft)
    end

    update :approve_and_submit do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :weather]
      require_atomic? false
      change set_attribute(:status, :submitted)
      change set_attribute(:submitted_at, &DateTime.utc_now/0)
      change Sitevoice.Reporting.Changes.DispatchIntegrations
    end

    update :mark_failed do
      change set_attribute(:status, :failed)
    end

    update :edit_draft do
      accept [:labor, :progress, :equipment, :materials, :delays, :safety, :weather, :pdf_key]
    end

    read :read do
      primary? true
      prepare build(load: [:pdf_url, :photos])
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [date: :desc])
    end

    read :list_for_date_range do
      argument :project_id, :uuid, allow_nil?: false
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      filter expr(project_id == ^arg(:project_id) and date >= ^arg(:from) and date <= ^arg(:to))
      prepare build(sort: [date: :desc])
    end

    destroy :destroy do
      require_atomic? false
      change before_action(fn changeset, _ ->
        if changeset.data.status == :submitted do
          Ash.Changeset.add_error(changeset, "Cannot delete a submitted log")
        else
          changeset
        end
      end)
    end
  end

  policies do
    policy action(:submit_recording) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
    end

    policy action([:apply_transcript, :apply_structure, :mark_failed]) do
      authorize_if actor_absent()
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:edit_draft) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:approve_and_submit) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:read) do
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end

    policy action(:destroy) do
      forbid_if expr(status == :submitted)
      authorize_if relates_to_actor_via(:foreman)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end
  end

  paper_trail do
    store_action_name? true
    attributes_as_attributes [:organization_id]
  end

  json_api do
    type "daily_log"

    routes do
      base "/daily-logs"
      index :read
      get :read
      post :submit_recording
      patch :approve_and_submit, route: "/:id/submit"
      patch :edit_draft, route: "/:id/draft"
      delete :destroy
    end
  end
end
