defmodule Sitevoice.Reporting.Reactors.ProcessRecording do
  use Ash.Reactor

  input :log_id
  input :organization_id

  step :set_tenant, Sitevoice.Steps.SetTenant do
    argument :organization_id, input(:organization_id)
  end

  step :fetch_log, Sitevoice.Steps.FetchLog do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    wait_for :set_tenant
  end

  step :fetch_audio, Sitevoice.Steps.FetchFromTigris do
    argument :key, result(:fetch_log, [:audio_key])
  end

  step :transcribe, Sitevoice.Steps.TranscribeWhisper do
    argument :audio, result(:fetch_audio)
    argument :language, result(:fetch_log, [:foreman, :preferred_language])
  end

  update :save_transcript, Sitevoice.Reporting.DailyLog, :apply_transcript do
    initial result(:fetch_log)
    tenant input(:organization_id)
    inputs %{transcript: result(:transcribe)}
    undo :always
    undo_action :undo_apply_transcript
  end

  step :structure, Sitevoice.Steps.StructureWithClaude do
    argument :transcript, result(:transcribe)
    async? true
  end

  step :caption_photos, Sitevoice.Steps.CaptionPhotos do
    argument :photo_keys, result(:fetch_log, [:photos])
    argument :transcript, result(:transcribe)
    argument :organization_id, input(:organization_id)
    async? true
  end

  update :save_structure, Sitevoice.Reporting.DailyLog, :apply_structure do
    initial result(:save_transcript)
    tenant input(:organization_id)
    inputs %{
      labor: result(:structure, [:labor]),
      progress: result(:structure, [:progress]),
      equipment: result(:structure, [:equipment]),
      materials: result(:structure, [:materials]),
      delays: result(:structure, [:delays]),
      safety: result(:structure, [:safety]),
      accuracy_score: result(:structure, [:accuracy_score])
    }
    undo :always
    undo_action :undo_apply_structure
  end

  step :generate_pdf, Sitevoice.Steps.GeneratePdf do
    argument :log, result(:save_structure)
  end

  step :store_pdf, Sitevoice.Steps.StoreTigris do
    argument :binary, result(:generate_pdf)
    argument :key, input(:log_id)
    argument :organization_id, input(:organization_id)
    argument :project_id, result(:fetch_log, [:project_id])
  end

  update :save_pdf_key, Sitevoice.Reporting.DailyLog, :update_pdf do
    initial result(:fetch_log)
    tenant input(:organization_id)
    inputs %{pdf_key: result(:store_pdf, [:key])}
    wait_for :store_pdf
  end

  step :notify, Sitevoice.Steps.BroadcastReady do
    argument :log_id, input(:log_id)
    argument :organization_id, input(:organization_id)
    argument :pdf_url, result(:store_pdf, [:url])
  end
end
