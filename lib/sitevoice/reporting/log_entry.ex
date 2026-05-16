defmodule Sitevoice.Reporting.LogEntry do
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
    table "log_entries"
    repo Sitevoice.Repo

    custom_indexes do
      index [:organization_id, :daily_log_id, :captured_at],
        name: "log_entries_org_log_captured_idx"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :organization_id, :uuid, allow_nil?: false, public?: false

    attribute :type, :atom,
      allow_nil?: false,
      constraints: [one_of: [:voice_memo, :text_note, :photo]]

    attribute :audio_key, :string
    attribute :audio_duration, :integer
    attribute :transcript, :string
    attribute :text, :string
    attribute :photo_key, :string
    attribute :caption, :string
    attribute :captured_at, :utc_datetime_usec, allow_nil?: false
    attribute :sort_order, :integer, default: 0

    attribute :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:pending, :transcribing, :transcribed, :failed]],
      default: :pending

    timestamps()
  end

  relationships do
    belongs_to :organization, Sitevoice.Accounts.Organization, allow_nil?: false
    belongs_to :daily_log, Sitevoice.Reporting.DailyLog, allow_nil?: false
  end

  calculations do
    calculate :audio_url, :string, Sitevoice.Reporting.Calculations.EntryAudioUrl
    calculate :photo_url, :string, Sitevoice.Reporting.Calculations.EntryPhotoUrl
  end

  actions do
    create :add_voice_memo do
      accept [:audio_key, :audio_duration, :captured_at, :sort_order]
      argument :daily_log_id, :uuid, allow_nil?: false
      change set_attribute(:type, :voice_memo)
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
      change set_attribute(:status, :pending)
      change Sitevoice.Reporting.Changes.EnqueueTranscription
    end

    create :add_text_note do
      accept [:text, :captured_at, :sort_order]
      argument :daily_log_id, :uuid, allow_nil?: false
      change set_attribute(:type, :text_note)
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
      change set_attribute(:status, :transcribed)
    end

    create :add_photo do
      accept [:photo_key, :captured_at, :sort_order]
      argument :daily_log_id, :uuid, allow_nil?: false
      change set_attribute(:type, :photo)
      change set_attribute(:organization_id, actor(:organization_id))
      change set_attribute(:daily_log_id, arg(:daily_log_id))
      change set_attribute(:status, :pending)
    end

    update :apply_transcript do
      accept [:transcript]
      change set_attribute(:status, :transcribed)
    end

    update :mark_transcription_failed do
      change set_attribute(:status, :failed)
    end

    update :apply_caption do
      accept [:caption]
    end

    destroy :remove_entry do
      require_atomic? false
      change before_action(fn changeset, _ ->
        log_id = changeset.data.daily_log_id
        org_id = changeset.data.organization_id

        case Ash.get(Sitevoice.Reporting.DailyLog, log_id, authorize?: false, tenant: org_id) do
          {:ok, %{status: :pending}} ->
            changeset

          {:ok, _} ->
            Ash.Changeset.add_error(
              changeset,
              "Cannot remove entry from a log that is being processed"
            )

          {:error, _} ->
            changeset
        end
      end)
    end

    read :read do
      primary? true
    end

    read :for_log do
      argument :daily_log_id, :uuid, allow_nil?: false
      filter expr(daily_log_id == ^arg(:daily_log_id))
      prepare build(sort: [captured_at: :asc, sort_order: :asc])
    end
  end

  policies do
    policy action([:add_voice_memo, :add_text_note, :add_photo]) do
      authorize_if actor_attribute_equals(:role, :foreman)
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:apply_transcript, :mark_transcription_failed, :apply_caption]) do
      authorize_if actor_absent()
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action(:remove_entry) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :org_admin)
    end

    policy action([:read, :for_log]) do
      authorize_if relates_to_actor_via([:daily_log, :foreman])
      authorize_if actor_attribute_equals(:role, :pm)
      authorize_if actor_attribute_equals(:role, :org_admin)
      authorize_if actor_attribute_equals(:role, :owner)
    end
  end
end
